import Foundation
import XCTest
@testable import TokenBar

final class HistoryStoreTests: XCTestCase {
    private var directory: URL!
    private var calendar: Calendar!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func day(_ string: String) -> Date { ISO8601DateFormatter().date(from: "\(string)T00:00:00Z")! }

    private func totals(_ input: Int, prompts: Int = 1, sessions: Int = 1, model: String = "m") -> DailyTotals {
        DailyTotals(models: [model: ModelDayTotals(tokens: TokenBreakdown(input: input), prompts: prompts)], sessions: sessions)
    }

    func testMergeKeepsDaysAfterTranscriptsArePruned() {
        let first = HistoryStore(directory: directory, calendar: calendar)
        first.recordDaily(provider: .claude, daily: [day("2026-08-01"): totals(100), day("2026-09-01"): totals(50)])
        // Later scan: August transcripts were pruned and September only partially remains.
        let second = HistoryStore(directory: directory, calendar: calendar)
        second.recordDaily(provider: .claude, daily: [day("2026-09-01"): totals(30, prompts: 3)])

        let history = second.history(provider: .claude, start: day("2026-08-01"), end: day("2026-09-01"))

        XCTAssertEqual(history.days.count, 32)
        XCTAssertEqual(history.days.first?.totals.tokens, 100)
        XCTAssertEqual(history.days.last?.totals.tokens, 50)
        XCTAssertEqual(history.days.last?.totals.prompts, 3)
        XCTAssertEqual(history.activeDays, 2)
        XCTAssertEqual(history.earliestRecord, day("2026-08-01"))
    }

    func testProvidersAreStoredSeparately() {
        let store = HistoryStore(directory: directory, calendar: calendar)
        store.recordDaily(provider: .codex, daily: [day("2026-09-01"): totals(7)])

        XCTAssertEqual(store.history(provider: .claude, start: day("2026-09-01"), end: day("2026-09-01")).totalTokens, 0)
        XCTAssertEqual(store.history(provider: .codex, start: day("2026-09-01"), end: day("2026-09-01")).totalTokens, 7)
    }

    func testLimitSamplesAreDeduplicatedUntilChangeOrInterval() {
        let store = HistoryStore(directory: directory, calendar: calendar)
        let start = day("2026-09-01").addingTimeInterval(3_600)
        let reset = start.addingTimeInterval(10_000)
        let limit = { (used: Double) in [RateLimit(label: "Session (5-hour)", usedFraction: used, resetsAt: reset)] }

        store.recordLimits(provider: .claude, limits: limit(0.10), at: start)
        store.recordLimits(provider: .claude, limits: limit(0.101), at: start.addingTimeInterval(900))
        store.recordLimits(provider: .claude, limits: limit(0.20), at: start.addingTimeInterval(1_800))
        store.recordLimits(provider: .claude, limits: limit(0.20), at: start.addingTimeInterval(1_800 + 3_600))

        // A fresh instance must reload the log rather than rely on in-memory state.
        let reloaded = HistoryStore(directory: directory, calendar: calendar)
        reloaded.recordLimits(provider: .claude, limits: limit(0.20), at: start.addingTimeInterval(1_800 + 3_700))
        let samples = reloaded.history(provider: .claude, start: day("2026-09-01"), end: day("2026-09-01")).samples

        XCTAssertEqual(samples.map(\.usedFraction), [0.10, 0.20, 0.20])
        XCTAssertEqual(samples.first?.window, .session)
    }

    func testRangeQueryExcludesOtherDaysAndMalformedLines() throws {
        let store = HistoryStore(directory: directory, calendar: calendar)
        store.recordLimits(provider: .claude, limits: [RateLimit(label: "Weekly (7-day)", usedFraction: 0.3, resetsAt: nil)],
                           at: day("2026-09-01").addingTimeInterval(60))
        store.recordLimits(provider: .claude, limits: [RateLimit(label: "Weekly (7-day)", usedFraction: 0.5, resetsAt: nil)],
                           at: day("2026-09-03").addingTimeInterval(60))
        let log = directory.appendingPathComponent("limits.jsonl")
        let handle = try FileHandle(forWritingTo: log)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("not json\n".utf8))
        try handle.close()

        let history = HistoryStore(directory: directory, calendar: calendar)
            .history(provider: .claude, start: day("2026-09-02"), end: day("2026-09-03"))

        XCTAssertEqual(history.samples.map(\.usedFraction), [0.5])
        XCTAssertEqual(history.days.count, 2)
    }

    func testClearRemovesEverything() {
        let store = HistoryStore(directory: directory, calendar: calendar)
        store.recordDaily(provider: .claude, daily: [day("2026-09-01"): totals(5)])
        store.clear()
        XCTAssertTrue(store.history(provider: .claude, start: day("2026-09-01"), end: day("2026-09-01")).isEmpty)
    }

    func testScannerDailyHistoryIncludesCodexEventsOlderThanThirtyDays() throws {
        let root = directory.appendingPathComponent("codex")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let lines = [
            #"{"type":"turn_context","payload":{"model":"gpt-test"}}"#,
            #"{"timestamp":"2026-06-01T12:00:00Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100}}}}"#,
            #"{"timestamp":"2026-09-08T12:00:00Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":20,"output_tokens":5}}}}"#
        ].joined(separator: "\n")
        try Data(lines.utf8).write(to: root.appendingPathComponent("session.jsonl"))
        let now = ISO8601DateFormatter().date(from: "2026-09-08T15:00:00Z")!

        let result = TranscriptScanner().scanWithHistory(provider: .codex, roots: [root], now: now)

        XCTAssertEqual(result.usage.totalTokens, 25)
        XCTAssertEqual(result.daily.values.map(\.tokens).sorted(), [25, 100])
        XCTAssertEqual(result.daily.values.first?.models.keys.first, "gpt-test")
        XCTAssertEqual(result.daily.values.map(\.sessions), [1, 1])
    }
}
