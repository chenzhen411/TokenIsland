import Foundation

/// A read-only client except for the user-initiated managed login flow.
/// Credentials stay with ChatGPT's app-server; TokenIsland never opens auth.json.
@MainActor public final class AppServerClient {
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var timeouts: [Int: Task<Void, Never>] = [:]
    private let executable: URL?
    private let arguments: [String]
    public var onAccountChanged: (() -> Void)?

    public init(executable: URL? = nil, arguments: [String] = ["app-server", "--listen", "stdio://"]) {
        self.executable = executable; self.arguments = arguments
    }
    public static func locateExecutable() -> URL? {
        let relative = "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
        let candidates = [
            "/Applications/ChatGPT.app/\(relative)",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/Applications/ChatGPT.app/\(relative)"
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:))
    }
    public func connect() async throws {
        if process?.isRunning == true { return }
        stop()
        guard let url = executable ?? Self.locateExecutable() else { throw ProviderError.missingApp }
        let child = Process(), stdin = Pipe(), stdout = Pipe()
        child.executableURL = url; child.arguments = arguments
        child.standardInput = stdin; child.standardOutput = stdout
        child.standardError = FileHandle.nullDevice
        child.currentDirectoryURL = FileManager.default.temporaryDirectory
        process = child; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor [weak self] in
                guard let self, self.process === child else { return }
                if data.isEmpty { self.stop() } else { self.receive(data) }
            }
        }
        child.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.process === child else { return }
                self.stop()
            }
        }
        do {
            try child.run()
            _ = try await request("initialize", params: [
                "clientInfo": ["name": "tokenisland", "title": "TokenIsland", "version": "0.2.1"],
                "capabilities": ["experimentalApi": true]
            ])
            try send(["method": "initialized", "params": [:]])
        } catch { stop(); throw error }
    }
    public func request(_ method: String, params: [String: Any]? = nil, timeout: UInt64 = 25) async throws -> Data {
        guard process?.isRunning == true else { throw ProviderError.disconnected }
        nextID += 1
        let id = nextID
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            var message: [String: Any] = ["id": id, "method": method]
            if let params { message["params"] = params }
            do { try send(message) }
            catch { pending.removeValue(forKey: id)?.resume(throwing: error); return }
            timeouts[id] = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: timeout * 1_000_000_000) }
                catch { return }
                self?.pending.removeValue(forKey: id)?.resume(throwing: ProviderError.timeout)
                self?.timeouts.removeValue(forKey: id)
            }
        }
    }
    private func send(_ value: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: value)
        data.append(10)
        try input?.write(contentsOf: data)
    }
    private func receive(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let id = message["id"] as? Int, let continuation = pending.removeValue(forKey: id) {
                timeouts.removeValue(forKey: id)?.cancel()
                if let error = message["error"] as? [String: Any] {
                    continuation.resume(throwing: ProviderError.server(error["message"] as? String ?? "unknown"))
                } else if let result = message["result"], let data = try? JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed]) {
                    continuation.resume(returning: data)
                } else { continuation.resume(throwing: ProviderError.disconnected) }
            } else if let method = message["method"] as? String {
                if method == "account/updated" || method == "account/login/completed" { onAccountChanged?() }
                // Reject any unexpected server request. This app never runs inference or tools.
                if let id = message["id"] {
                    try? send(["id": id, "error": ["code": -32601, "message": "Unsupported by TokenIsland"]])
                }
            }
        }
        if buffer.count > 16 * 1024 * 1024 { stop() }
    }
    public func stop() {
        output?.readabilityHandler = nil
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
        try? input?.close(); try? output?.close()
        input = nil; output = nil; process = nil; buffer.removeAll()
        timeouts.values.forEach { $0.cancel() }; timeouts.removeAll()
        let callbacks = pending.values; pending.removeAll()
        callbacks.forEach { $0.resume(throwing: ProviderError.disconnected) }
    }
}

@MainActor public final class ChatGPTProvider: UsageProvider {
    public let client: AppServerClient
    private let localReader = LocalUsageReader()
    public init(client: AppServerClient? = nil) { self.client = client ?? AppServerClient() }
    public func fetch() async throws -> UsageSnapshot? {
        try await client.connect()
        let decoder = JSONDecoder()
        let accountResponse = try decoder.decode(AccountResponse.self, from: await client.request("account/read", params: ["refreshToken": false]))
        guard let account = accountResponse.account else { return nil }
        guard account.type == "chatgpt" else { throw ProviderError.unsupportedAccount }
        var days: [DailyUsage]?, limits: LimitsResponse?, warnings: [String] = []
        do {
            days = try decoder.decode(UsageResponse.self, from: await client.request("account/usage/read")).dailyUsageBuckets
            if days == nil { warnings.append("服务端未返回日统计") }
        } catch { warnings.append("日统计暂不可用") }
        do { limits = try decoder.decode(LimitsResponse.self, from: await client.request("account/rateLimits/read")) }
        catch { warnings.append("额度暂不可用") }
        let now = Date()
        let localUsage: LocalUsage?
        if let id = limits?.accountId { localUsage = await localReader.read(accountID: id, now: now) }
        else { localUsage = nil }
        return UsageSnapshot(identity: limits?.accountId ?? account.email ?? "unknown-account", plan: account.planType ?? "ChatGPT", days: days,
                             limits: limits, updatedAt: now, warning: warnings.isEmpty ? nil : warnings.joined(separator: " · "), localUsage: localUsage)
    }
    public func login() async throws -> URL {
        try await client.connect()
        let data = try await client.request("account/login/start", params: ["type": "chatgpt", "useHostedLoginSuccessPage": true, "appBrand": "chatgpt"])
        struct Login: Decodable { let authUrl: String }
        let result = try JSONDecoder().decode(Login.self, from: data)
        guard let url = URL(string: result.authUrl), url.scheme == "https",
              let host = url.host, host == "chatgpt.com" || host == "auth.openai.com" || host == "auth0.openai.com" else {
            throw ProviderError.server("Invalid login URL")
        }
        return url
    }
    public func stop() { client.stop() }
}
