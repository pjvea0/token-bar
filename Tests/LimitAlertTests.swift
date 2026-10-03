import Foundation
import XCTest
@testable import TokenBar

final class LimitAlertTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-03T12:00:00Z")!
    private var reset: Date { now.addingTimeInterval(3_600) }

    private func usage(_ limits: [RateLimit], provider: ProviderID = .claude) -> ProviderUsage {
        ProviderUsage(id: provider, plan: "", limits: limits, days: [], models: [], historyScope: .allLocalHistory,
                      totalPrompts: 0, totalSessions: 0, activeDays: 0, updatedAt: now, status: nil, help: nil)
    }

    private func rules(enabled: Bool = true, thresholds: [Int] = [80, 95]) -> [AlertRule] {
        AlertRule.defaults.map { rule in
            var rule = rule
            rule.enabled = enabled && rule.provider == .claude
            rule.thresholds = thresholds
            return rule
        }
    }

    func testLimitWindowClassification() {
        XCTAssertEqual(RateLimit(label: "Session (5-hour)", usedFraction: 0, resetsAt: nil).window, .session)
        XCTAssertEqual(RateLimit(label: "5h window", usedFraction: 0, resetsAt: nil).window, .session)
        XCTAssertEqual(RateLimit(label: "Weekly (7-day)", usedFraction: 0, resetsAt: nil).window, .weekly)
        XCTAssertEqual(RateLimit(label: "Fable 5 Weekly", usedFraction: 0, resetsAt: nil).window, .weekly)
        XCTAssertNil(RateLimit(label: "Fable 5 Monthly", usedFraction: 0, resetsAt: nil).window)
    }

    func testFiresOncePerThresholdPerWindow() {
        let limit = RateLimit(label: "Session (5-hour)", usedFraction: 0.82, resetsAt: reset)
        let first = LimitAlertEvaluator.evaluate(usages: [usage([limit])], rules: rules(), fired: [], now: now)
        XCTAssertEqual(first.alerts.map(\.threshold), [80])

        let repeated = LimitAlertEvaluator.evaluate(usages: [usage([limit])], rules: rules(), fired: first.fired, now: now)
        XCTAssertTrue(repeated.alerts.isEmpty)

        let higher = RateLimit(label: "Session (5-hour)", usedFraction: 0.96, resetsAt: reset.addingTimeInterval(20))
        let next = LimitAlertEvaluator.evaluate(usages: [usage([higher])], rules: rules(), fired: repeated.fired, now: now)
        XCTAssertEqual(next.alerts.map(\.threshold), [95])
    }

    func testJumpingPastSeveralThresholdsSendsOnlyHighest() {
        let limit = RateLimit(label: "Weekly (7-day)", usedFraction: 0.97, resetsAt: reset)
        let result = LimitAlertEvaluator.evaluate(usages: [usage([limit])], rules: rules(), fired: [], now: now)
        XCTAssertEqual(result.alerts.map(\.threshold), [95])
        XCTAssertEqual(result.fired.count, 2)
    }

    func testRearmsAfterResetPasses() {
        let limit = RateLimit(label: "Session (5-hour)", usedFraction: 0.9, resetsAt: reset)
        let first = LimitAlertEvaluator.evaluate(usages: [usage([limit])], rules: rules(), fired: [], now: now)
        let later = now.addingTimeInterval(7_200)
        let nextCycle = RateLimit(label: "Session (5-hour)", usedFraction: 0.85, resetsAt: later.addingTimeInterval(18_000))

        let result = LimitAlertEvaluator.evaluate(usages: [usage([nextCycle])], rules: rules(), fired: first.fired, now: later)

        XCTAssertEqual(result.alerts.map(\.threshold), [80])
        XCTAssertFalse(result.fired.contains(where: { first.fired.contains($0) }))
    }

    func testDisabledRulesAndOtherProvidersAreIgnored() {
        let limit = RateLimit(label: "Weekly (7-day)", usedFraction: 1, resetsAt: reset)
        XCTAssertTrue(LimitAlertEvaluator.evaluate(usages: [usage([limit])], rules: rules(enabled: false), fired: [], now: now).alerts.isEmpty)
        XCTAssertTrue(LimitAlertEvaluator.evaluate(usages: [usage([limit], provider: .codex)], rules: rules(), fired: [], now: now).alerts.isEmpty)
    }

    func testLimitWithoutResetRearmsWhenUsageFalls() {
        let high = RateLimit(label: "Weekly (7-day)", usedFraction: 0.85, resetsAt: nil)
        let low = RateLimit(label: "Weekly (7-day)", usedFraction: 0.1, resetsAt: nil)
        let first = LimitAlertEvaluator.evaluate(usages: [usage([high])], rules: rules(), fired: [], now: now)
        let dropped = LimitAlertEvaluator.evaluate(usages: [usage([low])], rules: rules(), fired: first.fired, now: now)
        let again = LimitAlertEvaluator.evaluate(usages: [usage([high])], rules: rules(), fired: dropped.fired, now: now)
        XCTAssertEqual(again.alerts.map(\.threshold), [80])
    }

    func testAlertRulesRoundTrip() throws {
        let data = try JSONEncoder().encode(AlertRule.defaults)
        XCTAssertEqual(try JSONDecoder().decode([AlertRule].self, from: data), AlertRule.defaults)
        XCTAssertEqual(AlertRule.defaults.count, 4)
        XCTAssertFalse(AlertRule.defaults.contains(where: \.enabled))
    }
}
