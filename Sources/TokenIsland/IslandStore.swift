import AppKit
import SwiftUI
import CryptoKit
import TokenIslandCore

@MainActor final class IslandStore: ObservableObject {
    @Published var snapshot: UsageSnapshot?
    @Published var hours: [HourUsage] = []
    @Published var isRefreshing = false
    @Published var isLoggingIn = false
    @Published var signedOut = false
    @Published var error: String?
    @Published var isDemo = false
    @Published var expanded = false
    @Published var usageScope: UsageScope = .account {
        didSet {
            UserDefaults.standard.set(usageScope.rawValue, forKey: "usageScope")
            updateHours()
        }
    }
    @Published var notchWidth: CGFloat = 0
    @Published var headerHeight: CGFloat = 28
    @Published var detailHeight: CGFloat = 680
    @Published var selectedBucketID: String?
    @Published var selectedDate = Date()
    private let provider: ChatGPTProvider
    private var sampler = UsageSampler()
    private var identity: String?
    private var pollTask: Task<Void, Never>?
    private var generation = 0
    private var accountHours: [HourUsage] = []
    private var demoHours: [HourUsage] = []
    var onExpansionChange: ((Bool) -> Void)?

    init(provider: ChatGPTProvider? = nil) {
        self.provider = provider ?? ChatGPTProvider()
        usageScope = UsageScope(rawValue: UserDefaults.standard.string(forKey: "usageScope") ?? "") ?? .account
        self.provider.client.onAccountChanged = { [weak self] in
            guard let self, !self.isDemo else { return }
            self.generation += 1
            self.snapshot = nil; self.hours = []; self.accountHours = []; self.identity = nil
            self.isLoggingIn = false
            Task { [weak self] in
                while self?.isRefreshing == true {
                    do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
                }
                await self?.refresh()
            }
        }
    }
    var todayTokens: Int? { snapshot?.tokens(on: Date(), scope: usageScope) }
    var compactTokenText: String {
        if snapshot != nil, usageScope == .account, todayTokens == nil { return "待同步" }
        return TokenFormat.compact(todayTokens)
    }
    var selectedBucket: QuotaBucket? {
        let buckets = snapshot?.limits?.buckets ?? []
        return buckets.first { $0.id == selectedBucketID }?.bucket ?? buckets.first?.bucket
    }
    var quota: QuotaWindow? { selectedBucket?.primary ?? selectedBucket?.secondary }
    var quotaText: String { quota.map { "\(Int($0.remaining))%" } ?? "—" }
    var compactWidth: CGFloat { max(220, notchWidth + 160) }
    var expandedWidth: CGFloat { max(428, compactWidth) }
    var expandedHeight: CGFloat { headerHeight + detailHeight }
    var samplingNote: String {
        if isDemo { return "演示数据 · 小时曲线仅用于预览" }
        if usageScope == .local { return "本机桌面任务事件 · 按本地时间分组" }
        return "账号日累计增量采样 · 非服务端小时明细"
    }
    var sourceNote: String {
        usageScope == .account ? "账号日统计覆盖服务端已汇总活动 · 可能延迟" : "今日与小时为本机任务 · 日历仍为账号日统计"
    }
    private func updateHours() {
        if isDemo { hours = demoHours }
        else { hours = usageScope == .account ? accountHours : snapshot?.localUsage?.hours ?? [] }
    }

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { break }
            }
        }
    }
    func refresh() async {
        guard !isRefreshing, !isDemo else { return }
        isRefreshing = true
        let currentGeneration = generation
        defer { isRefreshing = false }
        do {
            let result = try await provider.fetch()
            guard currentGeneration == generation else { return }
            error = nil; signedOut = result == nil
            guard let result else {
                snapshot = nil; hours = []; accountHours = []; identity = nil; sampler = UsageSampler()
                return
            }
            if identity != result.identity {
                identity = result.identity
                sampler = loadSampler(for: result.identity)
            }
            snapshot = result
            sampler.observe(total: result.tokens(on: result.updatedAt, scope: .account), at: result.updatedAt)
            accountHours = sampler.today(at: result.updatedAt)
            updateHours()
            saveSampler(for: result.identity)
        } catch {
            guard currentGeneration == generation else { return }
            self.error = error.localizedDescription
        }
    }
    func login() {
        guard !isLoggingIn, !isDemo else { return }
        isLoggingIn = true; error = nil
        Task {
            do {
                let url = try await provider.login()
                if !NSWorkspace.shared.open(url) {
                    isLoggingIn = false; error = "无法打开浏览器，请检查默认浏览器设置。"
                }
            } catch { isLoggingIn = false; self.error = error.localizedDescription }
        }
    }
    func openChatGPT() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.chat") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        } else { NSWorkspace.shared.open(URL(string: "https://chatgpt.com/")!) }
    }
    func openUsage() { NSWorkspace.shared.open(URL(string: "https://chatgpt.com/#settings/Usage")!) }
    func setExpanded(_ value: Bool) {
        guard expanded != value else { return }
        if let onExpansionChange { onExpansionChange(value) }
        else { expanded = value }
    }
    func toggleExpanded() { setExpanded(!expanded) }
    func setDemo(_ value: Bool) {
        generation += 1; provider.stop()
        isDemo = value; error = nil; signedOut = false; isLoggingIn = false
        snapshot = nil; hours = []; accountHours = []; identity = nil; selectedBucketID = nil
        if value {
            let now = Date(), calendar = Calendar.current
            let days = DayKey.recentDates(now: now).enumerated().map { index, date in
                DailyUsage(startDate: DayKey.string(date), tokens: index == 29 ? 128_460 : (index % 7 == 2 ? 0 : Int(22_000 + abs(sin(Double(index) * 1.73)) * 165_000)))
            }
            let data = Data("""
            {"rateLimits":{"limitId":"codex","limitName":"ChatGPT Work","primary":{"usedPercent":28,"windowDurationMins":300,"resetsAt":\(now.addingTimeInterval(9420).timeIntervalSince1970)},"secondary":{"usedPercent":46,"windowDurationMins":10080,"resetsAt":\(now.addingTimeInterval(242000).timeIntervalSince1970)}}}
            """.utf8)
            let today = calendar.startOfDay(for: now)
            demoHours = (0...calendar.component(.hour, from: now)).map { h in
                HourUsage(hour: calendar.date(byAdding: .hour, value: h, to: today)!, tokens: h < 7 ? 0 : Int(abs(sin(Double(h) * 1.3)) * 15000 + 3000))
            }
            snapshot = UsageSnapshot(identity: "demo", plan: "Plus", days: days, limits: try? JSONDecoder().decode(LimitsResponse.self, from: data), updatedAt: now,
                                     localUsage: LocalUsage(day: DayKey.string(now), hours: demoHours, sessionCount: 1))
            updateHours()
        } else {
            Task { [weak self] in
                while self?.isRefreshing == true {
                    do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
                }
                self?.start()
            }
        }
    }
    private func cacheURL(for account: String) -> URL {
        let hash = SHA256.hash(data: Data(account.utf8)).map { String(format: "%02x", $0) }.joined()
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("TokenIsland", isDirectory: true).appendingPathComponent("\(hash).json")
    }
    private func loadSampler(for account: String) -> UsageSampler {
        guard account != "unknown-account", let data = try? Data(contentsOf: cacheURL(for: account)),
              let result = try? JSONDecoder().decode(UsageSampler.self, from: data) else { return UsageSampler() }
        return result
    }
    private func saveSampler(for account: String) {
        guard account != "unknown-account" else { return }
        let url = cacheURL(for: account)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(sampler)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { self.error = "小时采样无法保存到本机，退出后将丢失。" }
    }
    func stop() { pollTask?.cancel(); provider.stop() }
}
