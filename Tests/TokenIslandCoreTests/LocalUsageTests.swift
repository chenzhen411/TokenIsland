import Foundation
import Testing
@testable import TokenIslandCore

private func localCalendar() -> Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(secondsFromGMT: 0)!
    return value
}
private func localDate(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
private func metadata(account: String = "account-a", originator: String = "Codex Desktop") -> Data {
    Data("""
    {"type":"session_meta","payload":{"creator_account_id":"\(account)","originator":"\(originator)","model_provider":"openai"}}
    """.utf8)
}
private func tokenEvent(_ total: Int, last: Int, timestamp: String = "2026-10-28T09:05:00.000Z") -> Data {
    Data("""
    {"type":"event_msg","timestamp":"\(timestamp)","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":\(total)},"last_token_usage":{"total_tokens":\(last)}}}}
    """.utf8)
}

@Test func localEventsAreScopedToDesktopAndActiveAccount() {
    let now = localDate("2026-10-28T12:00:00Z")
    for header in [metadata(account: "other-account"), metadata(originator: "Codex CLI")] {
        var counter = SessionTokenCounter(accountID: "account-a", day: now, calendar: localCalendar())
        counter.ingest(header); counter.ingest(tokenEvent(100, last: 100))
        #expect(!counter.eligible)
        #expect(counter.hours.isEmpty)
    }
}

@Test func localEventsDeduplicateCumulativeNotificationsAndSkipInheritedForkUsage() {
    var counter = SessionTokenCounter(accountID: "account-a", day: localDate("2026-10-28T12:00:00Z"), calendar: localCalendar())
    counter.ingest(metadata())
    counter.ingest(tokenEvent(10000, last: 250)) // Inherited total: do not count the parent.
    counter.ingest(tokenEvent(10300, last: 300))
    counter.ingest(tokenEvent(10300, last: 300)) // Duplicate notification.
    counter.ingest(tokenEvent(10200, last: 300)) // Correction.
    counter.ingest(tokenEvent(10400, last: 200))
    #expect(counter.eligible)
    #expect(counter.hours.count == 1)
    #expect(counter.hours.first?.tokens == 400)
}

@Test func localEventsUsePreviousDayAsBaselineAndGroupByHour() {
    var counter = SessionTokenCounter(accountID: "account-a", day: localDate("2026-10-28T12:00:00Z"), calendar: localCalendar())
    counter.ingest(metadata())
    counter.ingest(tokenEvent(1000, last: 1000, timestamp: "2026-10-27T23:59:00Z"))
    counter.ingest(tokenEvent(1200, last: 200, timestamp: "2026-10-28T08:00:00.123Z"))
    counter.ingest(tokenEvent(1500, last: 300, timestamp: "2026-10-28T09:00:00Z"))
    #expect(counter.hours.map(\.tokens) == [200, 300])
    #expect(counter.hours.map { localCalendar().component(.hour, from: $0.hour) } == [8, 9])
}

@Test func localReaderCachesChangedFilesAndIsolatesAccounts() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("session.jsonl")
    var data = metadata(); data.append(10); data.append(tokenEvent(100, last: 100)); data.append(10)
    try data.write(to: file)
    let now = localDate("2026-10-28T12:00:00Z")
    let reader = LocalUsageReader(root: root)
    let first = await reader.read(accountID: "account-a", now: now, calendar: localCalendar())
    #expect(first?.total == 100)
    #expect(first?.sessionCount == 1)
    let repeated = await reader.read(accountID: "account-a", now: now, calendar: localCalendar())
    #expect(repeated?.total == 100)
    data.append(tokenEvent(250, last: 150)); data.append(10)
    try data.write(to: file)
    let updated = await reader.read(accountID: "account-a", now: now, calendar: localCalendar())
    #expect(updated?.total == 250)
    let otherAccount = await reader.read(accountID: "account-b", now: now, calendar: localCalendar())
    #expect(otherAccount == nil)
}
