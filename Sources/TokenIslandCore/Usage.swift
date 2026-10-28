import Foundation

public struct AccountResponse: Decodable {
    public let account: Account?
    public struct Account: Decodable {
        public let type: String
        public let email: String?
        public let planType: String?
    }
}

public struct DailyUsage: Codable, Identifiable, Equatable {
    public var id: String { startDate }
    public let startDate: String
    public let tokens: Int
    public init(startDate: String, tokens: Int) {
        self.startDate = startDate
        self.tokens = max(0, tokens)
    }
}

public struct UsageResponse: Decodable {
    public let dailyUsageBuckets: [DailyUsage]?
}

public struct QuotaWindow: Codable, Equatable {
    public let usedPercent: Double
    public let windowDurationMins: Int?
    public let resetsAt: TimeInterval?
    public var remaining: Double { min(100, max(0, 100 - usedPercent)) }
    public var label: String {
        guard let minutes = windowDurationMins else { return "当前窗口" }
        if minutes == 10080 { return "每周额度" }
        if minutes >= 1440 { return "\(minutes / 1440) 天额度" }
        if minutes >= 60 { return "\(minutes / 60) 小时额度" }
        return "\(minutes) 分钟额度"
    }
    public init(usedPercent: Double, windowDurationMins: Int?, resetsAt: TimeInterval?) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }
}

public struct QuotaBucket: Decodable {
    public let limitId: String?
    public let limitName: String?
    public let primary: QuotaWindow?
    public let secondary: QuotaWindow?
}

public struct LimitsResponse: Decodable {
    public let accountId: String?
    public let rateLimits: QuotaBucket?
    public let rateLimitsByLimitId: [String: QuotaBucket]?

    // Keep buckets separate: percentages from different models cannot be added.
    public var buckets: [(id: String, bucket: QuotaBucket)] {
        if let all = rateLimitsByLimitId, !all.isEmpty {
            return all.keys.sorted { a, b in
                if a == "codex" { return b != "codex" }
                if b == "codex" { return false }
                return a < b
            }.map { ($0, all[$0]!) }
        }
        if let legacy = rateLimits { return [(legacy.limitId ?? "default", legacy)] }
        return []
    }
}

public enum UsageScope: String, CaseIterable {
    case account, local
    public var title: String { self == .account ? "当前账号" : "本机实时" }
}

public struct UsageSnapshot {
    public let identity: String
    public let plan: String
    public let days: [DailyUsage]?
    public let limits: LimitsResponse?
    public let updatedAt: Date
    public let warning: String?
    public let localUsage: LocalUsage?
    public init(identity: String, plan: String, days: [DailyUsage]?, limits: LimitsResponse?, updatedAt: Date, warning: String? = nil, localUsage: LocalUsage? = nil) {
        self.identity = identity; self.plan = plan; self.days = days
        self.limits = limits; self.updatedAt = updatedAt; self.warning = warning; self.localUsage = localUsage
    }
    public func tokens(on date: Date, scope: UsageScope = .account, calendar: Calendar = .current) -> Int? {
        let key = DayKey.string(date, calendar: calendar)
        if scope == .local { return localUsage?.day == key ? localUsage?.total : nil }
        return days?.first { $0.startDate == key }?.tokens
    }
    public var latestAccountDay: DailyUsage? { days?.max { $0.startDate < $1.startDate } }
}

public enum DayKey {
    public static func string(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    public static func recentDates(now: Date, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0..<30).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }
}

public enum TokenFormat {
    public static func compact(_ tokens: Int?) -> String {
        guard let tokens else { return "—" }
        if tokens >= 1_000_000 { return String(format: "%.2fM", Double(tokens) / 1_000_000) }
        if tokens >= 1_000 { return String(format: "%.1fK", Double(tokens) / 1_000) }
        return "\(tokens)"
    }
}

@MainActor public protocol UsageProvider: AnyObject {
    func fetch() async throws -> UsageSnapshot?
    func login() async throws -> URL
    func stop()
}

public enum ProviderError: LocalizedError {
    case missingApp, disconnected, timeout, server(String), unsupportedAccount
    public var errorDescription: String? {
        switch self {
        case .missingApp: return "未找到 ChatGPT 的用量服务。请安装或更新 ChatGPT Mac 应用。"
        case .disconnected: return "ChatGPT 用量服务已断开，请重试。"
        case .timeout: return "连接 ChatGPT 超时，请检查网络后重试。"
        case .server: return "ChatGPT 暂时无法提供用量数据，请稍后重试。"
        case .unsupportedAccount: return "当前连接使用 API Key。请使用 ChatGPT 账号登录以读取订阅额度。"
        }
    }
}
