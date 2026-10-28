import Foundation

public struct HourUsage: Codable, Identifiable, Equatable {
    public var id: Date { hour }
    public let hour: Date
    public var tokens: Int
    public init(hour: Date, tokens: Int) { self.hour = hour; self.tokens = tokens }
}

/// Observed deltas, never a reconstruction of pre-launch history.
public struct UsageSampler: Codable {
    public private(set) var hours: [HourUsage] = []
    private var previousDate: Date?
    private var previousTotal: Int?
    public init() {}

    public mutating func observe(total: Int?, at date: Date, calendar: Calendar = .current) {
        let sameDay = previousDate.map { calendar.isDate(date, inSameDayAs: $0) } ?? false
        let baseline = sameDay ? max(previousTotal ?? 0, total ?? 0) : total
        defer { previousDate = date; previousTotal = total == nil ? nil : baseline }
        guard let total, let previousTotal, let previousDate,
              calendar.isDate(date, inSameDayAs: previousDate),
              date.timeIntervalSince(previousDate) > 0,
              date.timeIntervalSince(previousDate) <= 300,
              total >= previousTotal,
              let hour = calendar.dateInterval(of: .hour, for: date)?.start else { return }
        let delta = total - previousTotal
        if let i = hours.firstIndex(where: { $0.hour == hour }) { hours[i].tokens += delta }
        else { hours.append(HourUsage(hour: hour, tokens: delta)) }
        let cutoff = calendar.date(byAdding: .day, value: -32, to: date)!
        hours.removeAll { $0.hour < cutoff }
    }
    public func today(at date: Date, calendar: Calendar = .current) -> [HourUsage] {
        hours.filter { calendar.isDate($0.hour, inSameDayAs: date) }.sorted { $0.hour < $1.hour }
    }
}
