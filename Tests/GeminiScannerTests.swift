import Foundation
import SQLite3
import XCTest
@testable import TokenBar

final class GeminiScannerTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Gemini CLI

    func testGeminiCLIJSONChatSubtractsCachedInputAndCountsThoughtsAsOutput() throws {
        let chats = directory.appendingPathComponent("tmp/abc123/chats")
        try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
        try Data(#"""
        {"sessionId":"s1","messages":[
          {"id":"u1","type":"user","timestamp":"2026-10-01T10:00:00.000Z","content":"hi"},
          {"id":"g1","type":"gemini","timestamp":"2026-10-01T10:00:05.123Z","model":"gemini-2.5-pro",
           "tokens":{"input":1000,"output":50,"cached":400,"thoughts":30,"tool":10,"total":1090}},
          {"id":"g1","type":"gemini","timestamp":"2026-10-01T10:00:05.123Z","model":"gemini-2.5-pro",
           "tokens":{"input":1000,"output":50,"cached":400,"thoughts":30,"tool":10,"total":1090}},
          {"id":"g2","type":"gemini","timestamp":"2026-10-01T10:01:00Z","tokens":{"input":0,"output":0}}
        ]}
        """#.utf8).write(to: chats.appendingPathComponent("session-1.json"))
        try Data("{not json".utf8).write(to: chats.appendingPathComponent("session-broken.json"))

        let usage = GeminiScanner().scanWithHistory(home: directory, now: date("2026-10-02T00:00:00Z")).usage

        XCTAssertEqual(usage.models.count, 1)
        XCTAssertEqual(usage.models.first?.name, "gemini-2.5-pro")
        XCTAssertEqual(usage.models.first?.tokens, TokenBreakdown(input: 610, output: 80, cacheRead: 400))
        XCTAssertEqual(usage.totalPrompts, 1)
        XCTAssertEqual(usage.totalSessions, 1)
    }

    func testGeminiCLIJSONLChatReadsSessionHeaderAndSkipsMalformedLines() throws {
        let chats = directory.appendingPathComponent("tmp/def456/chats")
        try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
        try Data("""
        {"sessionId":"s2","projectHash":"def456"}
        not json
        {"id":"g1","type":"gemini","timestamp":"2026-10-01T09:00:00Z","model":"gemini-2.5-flash","tokens":{"input":200,"output":20,"cached":0}}
        {"id":"g2","type":"gemini","timestamp":"2026-10-01T09:05:00Z","model":"gemini-2.5-flash","tokens":{"input":300,"output":30,"cached":100}}
        """.utf8).write(to: chats.appendingPathComponent("session-2.jsonl"))

        let events = GeminiCLIChatParser().events(root: directory.appendingPathComponent("tmp"))

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(Set(events.map(\.session)), ["s2"])
        XCTAssertEqual(events.reduce(0) { $0 + $1.tokens.total }, 200 + 20 + 200 + 30 + 100)
    }

    // MARK: Antigravity

    func testProtobufReaderRejectsTruncatedInput() {
        XCTAssertNil(ProtobufMessage(Data([0x0A, 0x05, 0x01])))
        XCTAssertNil(ProtobufMessage(Data([0x80])))
        XCTAssertEqual(ProtobufMessage(Data([0x08, 0x96, 0x01]))?.int(1), 150)
    }

    func testAntigravityGenerationsUseMatchingStepTimesAndModel() throws {
        let conversations = directory.appendingPathComponent("antigravity/conversations")
        try FileManager.default.createDirectory(at: conversations, withIntermediateDirectories: true)
        let database = conversations.appendingPathComponent("conv-1.db")
        try makeAntigravityDatabase(at: database, generations: [
            generation(input: 1000, output: 190, cached: 0, model: "gemini-3-flash"),
            generation(input: 500, output: 90, cached: 16000, model: "gemini-3-flash"),
            Data([0xFF, 0xFF])
        ], steps: [
            (14, step(seconds: 1_790_000_000)),
            (15, step(seconds: 1_790_000_010)),
            (15, step(seconds: 1_790_086_400)),
            (15, step(seconds: 1_790_086_500))
        ])

        let events = AntigravityConversationReader().events(root: conversations)

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.map(\.model), ["gemini-3-flash", "gemini-3-flash"])
        XCTAssertEqual(events.map(\.session), ["conv-1", "conv-1"])
        XCTAssertEqual(events[0].tokens, TokenBreakdown(input: 1000, output: 190, cacheRead: 0))
        XCTAssertEqual(events[1].tokens, TokenBreakdown(input: 500, output: 90, cacheRead: 16000))
        XCTAssertEqual(events.map(\.date), [Date(timeIntervalSince1970: 1_790_000_010), Date(timeIntervalSince1970: 1_790_086_400)])
    }

    func testAntigravityFallsBackToLatestStepWhenStepsDoNotAlign() throws {
        let conversations = directory.appendingPathComponent("antigravity/conversations")
        try FileManager.default.createDirectory(at: conversations, withIntermediateDirectories: true)
        try makeAntigravityDatabase(at: conversations.appendingPathComponent("conv-2.db"),
                                    generations: [generation(input: 10, output: 5, cached: 0, model: nil)],
                                    steps: [(14, step(seconds: 1_790_000_000)), (14, step(seconds: 1_790_000_500))])

        let events = AntigravityConversationReader().events(root: conversations)

        XCTAssertEqual(events.first?.date, Date(timeIntervalSince1970: 1_790_000_500))
        XCTAssertEqual(events.first?.model, "antigravity")
    }

    func testAntigravityDatabaseWithoutExpectedTablesIsSkipped() throws {
        let conversations = directory.appendingPathComponent("antigravity/conversations")
        try FileManager.default.createDirectory(at: conversations, withIntermediateDirectories: true)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(conversations.appendingPathComponent("other.db").path, &db), SQLITE_OK)
        sqlite3_exec(db, "CREATE TABLE unrelated (x integer)", nil, nil, nil)
        sqlite3_close(db)
        try Data("not sqlite".utf8).write(to: conversations.appendingPathComponent("garbage.db"))

        XCTAssertTrue(AntigravityConversationReader().events(root: conversations).isEmpty)
    }

    func testAntigravityScanNeverModifiesSourceFiles() throws {
        let conversations = directory.appendingPathComponent("antigravity/conversations")
        try FileManager.default.createDirectory(at: conversations, withIntermediateDirectories: true)
        let database = conversations.appendingPathComponent("conv-3.db")
        let writer = try makeAntigravityDatabase(at: database, generations: [generation(input: 10, output: 5, cached: 0, model: "m")],
                                                 steps: [(15, step(seconds: 1_790_000_000))], keepOpen: true)
        defer { sqlite3_close(writer) }
        let before = try snapshot(conversations)

        let events = AntigravityConversationReader().events(root: conversations)

        XCTAssertEqual(events.count, 1, "rows still in the WAL must be visible through the copy")
        XCTAssertEqual(try snapshot(conversations), before, "source database, WAL, and shared memory must be byte-identical")
    }

    func testMergesGeminiCLIAndAntigravityIntoOneProvider() throws {
        let chats = directory.appendingPathComponent("tmp/p/chats")
        let conversations = directory.appendingPathComponent("antigravity/conversations")
        try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: conversations, withIntermediateDirectories: true)
        try Data(#"{"sessionId":"cli","messages":[{"id":"g","type":"gemini","timestamp":"2026-09-20T12:00:00Z","model":"gemini-2.5-pro","tokens":{"input":100,"output":10,"cached":0}}]}"#.utf8)
            .write(to: chats.appendingPathComponent("session.json"))
        let agyDate = date("2026-09-21T12:00:00Z")
        try makeAntigravityDatabase(at: conversations.appendingPathComponent("agy.db"),
                                    generations: [generation(input: 40, output: 4, cached: 0, model: "gemini-3-flash")],
                                    steps: [(15, step(seconds: UInt64(agyDate.timeIntervalSince1970)))])

        let result = GeminiScanner().scanWithHistory(home: directory, now: date("2026-09-22T00:00:00Z"))

        XCTAssertEqual(result.usage.id, .gemini)
        XCTAssertEqual(result.usage.historyScope, .allLocalHistory)
        XCTAssertEqual(Set(result.usage.models.map(\.name)), ["gemini-2.5-pro", "gemini-3-flash"])
        XCTAssertEqual(result.usage.totalTokens, 154)
        XCTAssertEqual(result.usage.totalSessions, 2)
        XCTAssertEqual(result.daily.count, 2)
    }

    func testGeminiHasNoAlertRules() {
        XCTAssertFalse(AlertRule.defaults.contains { $0.provider == .gemini })
        XCTAssertEqual(MenuBarDisplayStyle.weekly.label(provider: .gemini, limits: []), "Gm")
    }

    // MARK: Fixtures

    private func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }

    /// Mirrors the observed Antigravity layout: field 1 → 4 usage (2 input, 3 output, 5 cached), 1 → 19 model.
    private func generation(input: UInt64, output: UInt64, cached: UInt64, model: String?) -> Data {
        let usage = field(1, varint: 1318) + field(2, varint: input) + field(3, varint: output) + field(5, varint: cached)
        var root = field(3, varint: 1318) + field(4, bytes: usage)
        if let model { root += field(19, bytes: Data(model.utf8)) }
        return field(1, bytes: root)
    }

    private func step(seconds: UInt64) -> Data { field(1, bytes: field(1, varint: seconds) + field(2, varint: 0)) }

    private func field(_ number: UInt64, varint value: UInt64) -> Data { encode(number << 3) + encode(value) }
    private func field(_ number: UInt64, bytes: Data) -> Data { encode(number << 3 | 2) + encode(UInt64(bytes.count)) + bytes }

    private func encode(_ value: UInt64) -> Data {
        var value = value, data = Data()
        while value >= 0x80 { data.append(UInt8(value & 0x7F) | 0x80); value >>= 7 }
        data.append(UInt8(value))
        return data
    }

    @discardableResult
    private func makeAntigravityDatabase(at url: URL, generations: [Data], steps: [(Int, Data)], keepOpen: Bool = false) throws -> OpaquePointer? {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        sqlite3_exec(db, """
            PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0;
            CREATE TABLE gen_metadata (idx integer PRIMARY KEY, data blob, size integer NOT NULL DEFAULT 0);
            CREATE TABLE steps (idx integer PRIMARY KEY, step_type integer NOT NULL DEFAULT 0, metadata blob);
            """, nil, nil, nil)
        for (index, data) in generations.enumerated() { insert(db, "INSERT INTO gen_metadata (idx, data) VALUES (?, ?)", index, data) }
        for (index, step) in steps.enumerated() { insert(db, "INSERT INTO steps (idx, step_type, metadata) VALUES (?, \(step.0), ?)", index, step.1) }
        if keepOpen { return db }
        sqlite3_close(db)
        return nil
    }

    private func insert(_ db: OpaquePointer?, _ sql: String, _ index: Int, _ data: Data) {
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        sqlite3_bind_int(statement, 1, Int32(index))
        _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
        sqlite3_finalize(statement)
    }

    private func snapshot(_ directory: URL) throws -> [String: Data] {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        return try Dictionary(uniqueKeysWithValues: names.map { ($0, try Data(contentsOf: directory.appendingPathComponent($0))) })
    }
}
