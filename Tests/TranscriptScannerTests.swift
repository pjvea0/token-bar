import Foundation
import XCTest
@testable import TokenBar

final class TranscriptScannerTests: XCTestCase {
    func testFreshInstallAppearanceFollowsSystem() {
        XCTAssertEqual(AppAppearance.initial, .system)
        XCTAssertEqual(AppAppearance.allCases.map(\.rawValue), ["system", "light", "dark"])
        XCTAssertNil(AppAppearance.system.colorScheme)
        XCTAssertEqual(AppAppearance.light.colorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
    }

    func testFreshInstallMenuBarStyleIsIconOnly() {
        XCTAssertEqual(MenuBarDisplayStyle.initial, .iconOnly)
        XCTAssertEqual(MenuBarDisplayStyle.initial.label(provider: .claude, limits: []), "")
    }

    func testStandardGlobalShortcutHasExpectedDisplay() throws {
        XCTAssertEqual(GlobalShortcut.standard.displayText, "⌃⇧⌘R")
        let data = try JSONEncoder().encode(GlobalShortcut.standard)
        XCTAssertEqual(try JSONDecoder().decode(GlobalShortcut.self, from: data), .standard)
    }

    func testMenuBarStylesChooseRequestedLiveLimit() {
        let limits = [
            RateLimit(label: "Session (5-hour)", usedFraction: 0.126, resetsAt: nil),
            RateLimit(label: "Weekly (7-day)", usedFraction: 0.574, resetsAt: nil)
        ]

        XCTAssertEqual(MenuBarDisplayStyle.iconOnly.label(provider: .claude, limits: limits), "")
        XCTAssertEqual(MenuBarDisplayStyle.provider.label(provider: .claude, limits: limits), "Cl")
        XCTAssertEqual(MenuBarDisplayStyle.session.label(provider: .claude, limits: limits), "Cl 13%")
        XCTAssertEqual(MenuBarDisplayStyle.weekly.label(provider: .claude, limits: limits), "Cl 57%")
    }

    func testMenuBarLimitStyleFallsBackToProviderWhenLimitIsUnavailable() {
        XCTAssertEqual(MenuBarDisplayStyle.weekly.label(provider: .codex, limits: []), "Cx")
    }

    func testCodexRPCReaderWaitsForMatchingResponse() throws {
        let pipe = Pipe()
        let messages = [
            #"{"method":"notification","params":{}}"#,
            #"{"id":1,"result":{"ready":true}}"#,
            #"{"id":2,"result":{"account":{"planType":"pro"}}}"#
        ].joined(separator: "\n") + "\n"
        try pipe.fileHandleForWriting.write(contentsOf: Data(messages.utf8))
        defer { pipe.fileHandleForWriting.closeFile() }
        var reader = CodexRPCReader(handle: pipe.fileHandleForReading)

        let initialize = try reader.response(id: 1, timeoutSeconds: 1)
        let account = try reader.response(id: 2, timeoutSeconds: 1)

        XCTAssertEqual(initialize?["result"]?["ready"]?.bool, true)
        XCTAssertEqual(account?["result"]?["account"]?["planType"]?.string, "pro")
    }

    func testDecodesClaudeCredentialWithoutPersistingIt() throws {
        let data = Data(#"{"claudeAiOauth":{"accessToken":"secret-test-token","expiresAt":2000000000000,"rateLimitTier":"default_claude_max_20x","subscriptionType":"max"}}"#.utf8)

        let credential = ClaudeCredentialLoader().decode(data)

        XCTAssertEqual(credential?.accessToken, "secret-test-token")
        XCTAssertEqual(credential?.expiresAtMilliseconds, 2_000_000_000_000)
        XCTAssertEqual(credential?.rateLimitTier, "default_claude_max_20x")
        XCTAssertEqual(credential?.subscriptionType, "max")
    }

    func testClaudeLimitsIncludeFlatFallbackAndModelScopedWindows() throws {
        let data = Data(#"{"five_hour":{"utilization":0.5,"resets_at":"2026-09-09T12:00:00Z"},"seven_day_oauth_apps":null,"seven_day":{"utilization":4.0,"resets_at":"2026-09-14T12:00:00Z"},"limits":[{"kind":"weekly_scoped","scope":{"model":{"display_name":"Fable 5"}},"percent":12.0,"resets_at":"2026-09-14T12:00:00Z"}]}"#.utf8)
        let json = try JSONDecoder().decode(JSONValue.self, from: data)

        let limits = ClaudeLimitCollector().parseLimits(json)

        XCTAssertEqual(limits.map(\.label), ["Session (5-hour)", "Weekly (7-day)", "Fable 5 Weekly"])
        XCTAssertEqual(limits.map(\.usedFraction), [0.005, 0.04, 0.12])
        XCTAssertNotNil(limits[0].resetsAt)
    }

    func testScansClaudeTranscriptWithoutDoubleCountingMessageIDs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let line = #"{"type":"assistant","timestamp":"2026-09-08T12:00:00Z","sessionId":"s1","message":{"id":"m1","role":"assistant","model":"claude-test","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":2}}}"#
        try Data("\(line)\n\(line)\n".utf8).write(to: root.appendingPathComponent("session.jsonl"))

        let result = TranscriptScanner().scan(provider: .claude, root: root, now: ISO8601DateFormatter().date(from: "2026-09-08T15:00:00Z")!)

        XCTAssertEqual(result.totalPrompts, 1)
        XCTAssertEqual(result.totalSessions, 1)
        XCTAssertEqual(result.models.first?.tokens.total, 17)
    }

    func testScansCodexLastTurnUsageAndSubtractsCachedInput() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let lines = [
            #"{"type":"turn_context","payload":{"model":"gpt-test"}}"#,
            #"{"timestamp":"2026-09-08T12:00:00Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":20,"cached_input_tokens":5,"output_tokens":4}}}}"#
        ].joined(separator: "\n")
        try Data(lines.utf8).write(to: root.appendingPathComponent("session.jsonl"))

        let result = TranscriptScanner().scan(provider: .codex, root: root, now: ISO8601DateFormatter().date(from: "2026-09-08T15:00:00Z")!)

        XCTAssertEqual(result.models.first?.tokens.total, 24)
        XCTAssertEqual(result.models.first?.name, "gpt-test")
        XCTAssertEqual(result.models.first?.tokens.input, 15)
        XCTAssertEqual(result.models.first?.tokens.cacheRead, 5)
    }

    func testCodexHistoryUsesEventTimestampsForRollingThirtyDays() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let lines = [
            #"{"type":"turn_context","payload":{"model":"gpt-test"}}"#,
            #"{"timestamp":"2026-08-08T14:59:59Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100}}}}"#,
            #"{"timestamp":"2026-08-09T15:00:00Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":20}}}}"#,
            #"{"timestamp":"2026-09-08T15:00:01Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":200}}}}"#
        ].joined(separator: "\n")
        try Data(lines.utf8).write(to: root.appendingPathComponent("session.jsonl"))
        let now = ISO8601DateFormatter().date(from: "2026-09-08T15:00:00Z")!

        let result = TranscriptScanner().scan(provider: .codex, root: root, now: now)

        XCTAssertEqual(result.historyScope, .rollingDays(30))
        XCTAssertEqual(result.totalPrompts, 1)
        XCTAssertEqual(result.totalSessions, 1)
        XCTAssertEqual(result.activeDays, 1)
        XCTAssertEqual(result.totalTokens, 20)
    }

    func testClaudeHistoryKeepsEventsOlderThanThirtyDays() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let line = #"{"type":"assistant","timestamp":"2025-01-01T12:00:00Z","sessionId":"old-session","message":{"id":"old-message","role":"assistant","model":"claude-test","usage":{"input_tokens":10}}}"#
        try Data("\(line)\n".utf8).write(to: root.appendingPathComponent("session.jsonl"))
        let now = ISO8601DateFormatter().date(from: "2026-09-08T15:00:00Z")!

        let result = TranscriptScanner().scan(provider: .claude, root: root, now: now)

        XCTAssertEqual(result.historyScope, .allLocalHistory)
        XCTAssertEqual(result.totalTokens, 10)
        XCTAssertEqual(result.activeDays, 1)
    }
}
