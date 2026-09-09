import Foundation
import XCTest
@testable import TokenBar

final class TranscriptScannerTests: XCTestCase {
    func testDecodesClaudeCredentialWithoutPersistingIt() throws {
        let data = Data(#"{"claudeAiOauth":{"accessToken":"secret-test-token","expiresAt":2000000000000,"rateLimitTier":"default_claude_max_20x","subscriptionType":"max"}}"#.utf8)

        let credential = ClaudeCredentialLoader().decode(data)

        XCTAssertEqual(credential?.accessToken, "secret-test-token")
        XCTAssertEqual(credential?.expiresAtMilliseconds, 2_000_000_000_000)
        XCTAssertEqual(credential?.rateLimitTier, "default_claude_max_20x")
        XCTAssertEqual(credential?.subscriptionType, "max")
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

        let result = TranscriptScanner().scan(provider: .codex, root: root)

        XCTAssertEqual(result.models.first?.tokens.total, 24)
        XCTAssertEqual(result.models.first?.name, "gpt-test")
        XCTAssertEqual(result.models.first?.tokens.input, 15)
        XCTAssertEqual(result.models.first?.tokens.cacheRead, 5)
    }
}
