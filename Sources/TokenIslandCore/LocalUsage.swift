import Foundation

public struct LocalUsage: Equatable {
    public let day: String
    public let hours: [HourUsage]
    public let sessionCount: Int
    public var total: Int { hours.reduce(0) { $0 + $1.tokens } }
    public init(day: String, hours: [HourUsage], sessionCount: Int) {
        self.day = day; self.hours = hours; self.sessionCount = sessionCount
    }
}

/// Decodes only metadata and token counters, ignoring conversation fields.
public struct SessionTokenCounter {
    private struct Event: Decodable {
        let type: String
        let timestamp: String?
        let payload: Payload?
        struct Payload: Decodable {
            let type: String?
            let creator_account_id: String?
            let originator: String?
            let model_provider: String?
            let info: Info?
        }
        struct Info: Decodable {
            let total_token_usage: Count?
            let last_token_usage: Count?
        }
        struct Count: Decodable { let total_tokens: Int? }
    }
    public private(set) var eligible = false
    public private(set) var hours: [HourUsage] = []
    private var previousTotal: Int?
    private let accountID: String
    private let day: Date
    private let calendar: Calendar
    private let fractional: ISO8601DateFormatter
    private let plain = ISO8601DateFormatter()

    public init(accountID: String, day: Date, calendar: Calendar = .current) {
        self.accountID = accountID; self.day = day; self.calendar = calendar
        fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }
    public mutating func ingest(_ line: Data) {
        guard let text = String(data: line, encoding: .utf8),
              text.contains("\"session_meta\"") || text.contains("\"token_count\""),
              let event = try? JSONDecoder().decode(Event.self, from: line), let payload = event.payload else { return }
        if event.type == "session_meta" {
            let desktop = ["Codex Desktop", "ChatGPT", "ChatGPT Desktop"].contains(payload.originator ?? "")
            eligible = desktop && payload.creator_account_id == accountID && payload.model_provider == "openai"
            return
        }
        guard eligible, event.type == "event_msg", payload.type == "token_count",
              let total = payload.info?.total_token_usage?.total_tokens, total >= 0 else { return }
        let delta: Int
        if let previousTotal {
            // A repeated counter is a notification, not new consumption.
            // Counter corrections never create negative usage or double count a recovery.
            delta = max(0, total - previousTotal)
            self.previousTotal = max(previousTotal, total)
        } else {
            // Forks may inherit the parent's cumulative total. Count the first
            // event only if the last request fully explains that initial total.
            delta = payload.info?.last_token_usage?.total_tokens == total ? total : 0
            previousTotal = total
        }
        guard let stamp = event.timestamp, let date = fractional.date(from: stamp) ?? plain.date(from: stamp),
              calendar.isDate(date, inSameDayAs: day),
              let hour = calendar.dateInterval(of: .hour, for: date)?.start else { return }
        if let index = hours.firstIndex(where: { $0.hour == hour }) { hours[index].tokens += delta }
        else { hours.append(HourUsage(hour: hour, tokens: delta)) }
    }
}

/// Re-reads only changed session files; runs outside the UI's main actor.
public actor LocalUsageReader {
    private struct Cached {
        let modificationDate: Date
        let size: Int
        let counter: SessionTokenCounter
    }
    private var cache: [URL: Cached] = [:]
    private var accountID: String?
    private var dayKey: String?
    private let root: URL
    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")) { self.root = root }

    public func read(accountID: String, now: Date, calendar: Calendar = .current) -> LocalUsage? {
        let key = DayKey.string(now, calendar: calendar)
        if self.accountID != accountID || dayKey != key { cache.removeAll(); self.accountID = accountID; dayKey = key }
        let properties: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: properties, options: [.skipsHiddenFiles]) else { return nil }
        var active = Set<URL>()
        let start = calendar.startOfDay(for: now)
        for case let url as URL in files {
            guard url.pathExtension == "jsonl", let info = try? url.resourceValues(forKeys: Set(properties)),
                  info.isRegularFile == true, let changed = info.contentModificationDate, changed >= start,
                  let size = info.fileSize else { continue }
            active.insert(url)
            if let existing = cache[url], existing.modificationDate == changed, existing.size == size { continue }
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            var counter = SessionTokenCounter(accountID: accountID, day: now, calendar: calendar)
            var buffer = Data()
            while let chunk = try? handle.read(upToCount: 65536), !chunk.isEmpty {
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 10) {
                    counter.ingest(Data(buffer.prefix(upTo: newline)))
                    buffer.removeSubrange(...newline)
                }
                // Very large conversation lines contain no counters. Avoid retaining them.
                if buffer.count > 16 * 1024 * 1024 { buffer.removeAll() }
            }
            // Ignore an unfinished line while the app is still appending to the log.
            cache[url] = Cached(modificationDate: changed, size: size, counter: counter)
        }
        cache = cache.filter { active.contains($0.key) }
        let eligible = cache.values.filter { $0.counter.eligible }
        guard !eligible.isEmpty else { return nil }
        var totals: [Date: Int] = [:]
        for session in eligible {
            for hour in session.counter.hours { totals[hour.hour, default: 0] += hour.tokens }
        }
        return LocalUsage(day: key, hours: totals.keys.sorted().map { HourUsage(hour: $0, tokens: totals[$0]!) }, sessionCount: eligible.count)
    }
}
