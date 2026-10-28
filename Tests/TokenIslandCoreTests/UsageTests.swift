import Foundation
import Testing
@testable import TokenIslandCore

private func utcCalendar() -> Calendar {
    var result = Calendar(identifier: .gregorian)
    result.timeZone = TimeZone(secondsFromGMT: 0)!
    return result
}
private func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }

@Test func quotaClampsAndNamesWindows() {
    #expect(QuotaWindow(usedPercent: 120, windowDurationMins: 300, resetsAt: nil).remaining == 0)
    #expect(QuotaWindow(usedPercent: -5, windowDurationMins: 10080, resetsAt: nil).remaining == 100)
    #expect(QuotaWindow(usedPercent: 28, windowDurationMins: 300, resetsAt: nil).label == "5 小时额度")
    #expect(QuotaWindow(usedPercent: 28, windowDurationMins: nil, resetsAt: nil).label == "当前窗口")
}

@Test func multiBucketDataDoesNotFallBackToLegacyOrSumQuotas() throws {
    let json = #"{"rateLimits":{"primary":{"usedPercent":5}},"rateLimitsByLimitId":{"model-b":{"primary":{"usedPercent":80}},"codex":{"secondary":{"usedPercent":40}}}}"#
    let result = try JSONDecoder().decode(LimitsResponse.self, from: Data(json.utf8))
    #expect(result.buckets.count == 2)
    #expect(result.buckets.first?.id == "codex")
    #expect(result.buckets.first?.bucket.primary == nil)
    #expect(result.buckets.first?.bucket.secondary?.remaining == 60)
    #expect(result.buckets.last?.bucket.primary?.remaining == 20)
}

@Test func missingAndZeroUsageStayDistinct() throws {
    let missing = try JSONDecoder().decode(UsageResponse.self, from: Data(#"{"dailyUsageBuckets":null}"#.utf8))
    #expect(missing.dailyUsageBuckets == nil)
    let now = date("2026-10-28T08:00:00Z")
    let snapshot = UsageSnapshot(identity: "test", plan: "plus", days: [DailyUsage(startDate: "2026-10-27", tokens: 0)], limits: nil, updatedAt: now)
    #expect(snapshot.tokens(on: now, calendar: utcCalendar()) == nil)
    #expect(snapshot.tokens(on: now.addingTimeInterval(-86400), calendar: utcCalendar()) == 0)
    #expect(TokenFormat.compact(nil) == "—")
    #expect(TokenFormat.compact(0) == "0")
}

@Test func calendarUsesThirtyActualDatesAcrossMonthAndYearBoundaries() {
    let calendar = utcCalendar()
    let days = DayKey.recentDates(now: date("2026-01-03T12:00:00Z"), calendar: calendar)
    #expect(days.count == 30)
    #expect(DayKey.string(days.first!, calendar: calendar) == "2025-12-05")
    #expect(DayKey.string(days.last!, calendar: calendar) == "2026-01-03")
    #expect(Set(days).count == 30)
}

@Test func calendarHandlesDaylightSavingWithoutDuplicateDays() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let days = DayKey.recentDates(now: date("2026-11-04T18:00:00Z"), calendar: calendar)
    #expect(Set(days.map { DayKey.string($0, calendar: calendar) }).count == 30)
}

@Test func samplerCountsOnlyObservedDeltasOnceAndPersistsBaseline() throws {
    let calendar = utcCalendar(), first = date("2026-10-28T08:00:00Z")
    var sampler = UsageSampler()
    sampler.observe(total: 10000, at: first, calendar: calendar)
    #expect(sampler.hours.isEmpty) // Pre-launch usage is not attributed to the current hour.
    sampler.observe(total: 10400, at: first.addingTimeInterval(60), calendar: calendar)
    sampler.observe(total: 10400, at: first.addingTimeInterval(120), calendar: calendar)
    #expect(sampler.hours.first?.tokens == 400)
    let encoded = try JSONEncoder().encode(sampler)
    var restored = try JSONDecoder().decode(UsageSampler.self, from: encoded)
    restored.observe(total: 10500, at: first.addingTimeInterval(180), calendar: calendar)
    #expect(restored.hours.first?.tokens == 500)
}

@Test func samplerDoesNotInventUsageDuringSleepOrOnMissingData() {
    let calendar = utcCalendar(), first = date("2026-10-28T08:00:00Z")
    var sampler = UsageSampler()
    sampler.observe(total: 100, at: first, calendar: calendar)
    sampler.observe(total: 10000, at: first.addingTimeInterval(3600), calendar: calendar)
    #expect(sampler.hours.isEmpty)
    sampler.observe(total: nil, at: first.addingTimeInterval(3660), calendar: calendar)
    sampler.observe(total: 12000, at: first.addingTimeInterval(3720), calendar: calendar)
    #expect(sampler.hours.isEmpty)
}

@Test func samplerResetsAtMidnightAndHandlesCorrections() {
    let calendar = utcCalendar(), first = date("2026-10-28T23:59:00Z")
    var sampler = UsageSampler()
    sampler.observe(total: 10000, at: first, calendar: calendar)
    sampler.observe(total: 10, at: first.addingTimeInterval(60), calendar: calendar)
    #expect(sampler.hours.isEmpty)
    sampler.observe(total: 100, at: first.addingTimeInterval(120), calendar: calendar)
    #expect(sampler.hours.first?.tokens == 90)
    sampler.observe(total: 50, at: first.addingTimeInterval(180), calendar: calendar)
    #expect(sampler.hours.first?.tokens == 90)
    sampler.observe(total: 120, at: first.addingTimeInterval(240), calendar: calendar)
    #expect(sampler.hours.first?.tokens == 110)
    #expect(sampler.today(at: first, calendar: calendar).isEmpty)
}

@Test func accountNullMeansSignedOutAndApiKeyIsSeparate() throws {
    let decoder = JSONDecoder()
    let signedOut = try decoder.decode(AccountResponse.self, from: Data(#"{"account":null,"requiresOpenaiAuth":true}"#.utf8))
    #expect(signedOut.account == nil)
    let api = try decoder.decode(AccountResponse.self, from: Data(#"{"account":{"type":"apiKey"}}"#.utf8))
    #expect(api.account?.type == "apiKey")
}

private let fakeServer = #"""
import sys, json, time
for line in sys.stdin:
    m = json.loads(line)
    if 'id' not in m: continue
    method = m['method']
    if method == 'hang': continue
    if method == 'fail':
        response = {'id':m['id'], 'error':{'code':-1,'message':'test failure'}}
    else:
        response = {'id':m['id'], 'result':{'method':method}}
    wire = json.dumps(response)+'\n'
    sys.stdout.write(wire[:8]); sys.stdout.flush()
    time.sleep(0.01)
    sys.stdout.write(wire[8:]); sys.stdout.flush()
"""#

@Test @MainActor func rpcHandlesFragmentedMessagesAndServerErrors() async throws {
    let client = AppServerClient(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-u", "-c", fakeServer])
    defer { client.stop() }
    try await client.connect()
    let result = try await client.request("account/read")
    let object = try JSONSerialization.jsonObject(with: result) as! [String: String]
    #expect(object["method"] == "account/read")
    do { _ = try await client.request("fail"); Issue.record("Expected server failure") }
    catch { #expect(error is ProviderError) }
    // An error response must not poison subsequent requests.
    _ = try await client.request("account/rateLimits/read")
}

@Test @MainActor func rpcTimeoutLeavesClientUsableAndStopFailsOutstandingCalls() async throws {
    let client = AppServerClient(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-u", "-c", fakeServer])
    defer { client.stop() }
    try await client.connect()
    do { _ = try await client.request("hang", timeout: 1); Issue.record("Expected timeout") }
    catch { #expect(error.localizedDescription.contains("超时")) }
    _ = try await client.request("account/read")
    let pending = Task { try await client.request("hang") }
    try await Task.sleep(nanoseconds: 20_000_000)
    client.stop()
    do { _ = try await pending.value; Issue.record("Expected disconnection") }
    catch { #expect(error.localizedDescription.contains("断开")) }
}
