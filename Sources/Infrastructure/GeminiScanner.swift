import Foundation
import SQLite3

/// Local Gemini activity from two tools that share `~/.gemini`: Gemini CLI chat recordings and
/// Antigravity conversation databases. Neither exposes live quotas, so this is local-only (ADR 0006).
struct GeminiScanner: Sendable {
    var calendar = Calendar.current

    func scanWithHistory(home: URL, now: Date = .now) -> (usage: ProviderUsage, daily: [Date: DailyTotals]) {
        var accumulator = UsageAccumulator(calendar: calendar, now: now)
        GeminiCLIChatParser().events(root: home.appendingPathComponent("tmp")).forEach { accumulator.add($0) }
        AntigravityConversationReader().events(root: home.appendingPathComponent("antigravity/conversations")).forEach { accumulator.add($0) }
        return accumulator.finish(provider: .gemini, scope: .allLocalHistory)
    }
}

/// Gemini CLI records each chat under `tmp/<projectHash>/chats/` as one JSON document
/// (`{sessionId, messages: [...]}`) or, in newer versions, as JSONL with one record per line.
/// Only `gemini` messages carry `tokens`; `input` includes cached tokens and `thoughts` are
/// billed as output.
struct GeminiCLIChatParser: Sendable {
    func events(root: URL) -> [UsageEvent] {
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])?
            .compactMap { $0 as? URL }
            .filter { $0.deletingLastPathComponent().lastPathComponent == "chats" && ["json", "jsonl"].contains($0.pathExtension) } ?? []
        return files.flatMap(events(file:))
    }

    func events(file: URL) -> [UsageEvent] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        let fallbackDate = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
        let decoder = JSONDecoder()
        if file.pathExtension == "json" {
            guard let document = try? decoder.decode(JSONValue.self, from: data) else { return [] }
            let session = document["sessionId"]?.string ?? file.path
            return (document["messages"]?.array ?? []).compactMap { event($0, session: session, fallbackDate: fallbackDate) }
        }
        var session = file.path
        var result: [UsageEvent] = []
        for line in data.split(separator: 0x0A) {
            guard let record = try? decoder.decode(JSONValue.self, from: line) else { continue }
            if let id = record["sessionId"]?.string { session = id }
            if let event = event(record, session: session, fallbackDate: fallbackDate) { result.append(event) }
        }
        return result
    }

    private func event(_ message: JSONValue, session: String, fallbackDate: Date) -> UsageEvent? {
        guard message["type"]?.string == "gemini", let usage = message["tokens"] else { return nil }
        let cached = int(usage["cached"])
        let tokens = TokenBreakdown(input: max(0, int(usage["input"]) - cached) + int(usage["tool"]),
                                    output: int(usage["output"]) + int(usage["thoughts"]),
                                    cacheRead: cached)
        guard tokens.total > 0 else { return nil }
        return UsageEvent(id: message["id"]?.string.map { "gemini-cli:\($0)" }, session: session,
                          model: message["model"]?.string ?? "gemini",
                          date: message["timestamp"]?.string.flatMap(parseISO8601) ?? fallbackDate, tokens: tokens)
    }

    private func int(_ value: JSONValue?) -> Int { Int(value?.number ?? 0) }
}

/// Antigravity stores each conversation in `conversations/<uuid>.db`. The schema is undocumented;
/// field numbers below were mapped from real databases (see ADR 0006) and are read defensively:
///
/// - `gen_metadata.data`, one row per model generation: field 1 → 4 is usage
///   (2 uncached input, 3 output including thinking, 5 cached input) and 1 → 19 is the model ID.
/// - `steps.metadata`: field 1 → 1 is the step's creation time in seconds. Generation steps
///   (`step_type` 15) correspond one-to-one, in order, with `gen_metadata` rows.
struct AntigravityConversationReader: Sendable {
    static let generationStepType = 15

    func events(root: URL) -> [UsageEvent] {
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "db" }.flatMap(events(database:))
    }

    func events(database: URL) -> [UsageEvent] {
        let conversation = database.deletingPathExtension().lastPathComponent
        let fallbackDate = (try? database.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
        return withSnapshot(of: database) { db in
            let generations = rows(db, "SELECT data FROM gen_metadata ORDER BY idx").map(Self.generation)
            let stepTimes = rows(db, "SELECT metadata FROM steps WHERE step_type = \(Self.generationStepType) ORDER BY idx")
                .map(Self.stepTime)
            let latest = rows(db, "SELECT metadata FROM steps").compactMap(Self.stepTime).max() ?? fallbackDate
            let aligned = stepTimes.count == generations.count
            return generations.enumerated().compactMap { index, generation in
                guard let generation, generation.tokens.total > 0 else { return nil }
                // Without a one-to-one step match, date the generation by the conversation's last activity.
                let date = (aligned ? stepTimes[index] : nil) ?? latest
                return UsageEvent(id: "antigravity:\(conversation):\(index)", session: conversation,
                                  model: generation.model ?? "antigravity", date: date, tokens: generation.tokens)
            }
        } ?? []
    }

    static func generation(_ data: Data) -> (tokens: TokenBreakdown, model: String?)? {
        guard let root = ProtobufMessage(data)?.message(1), let usage = root.message(4) else { return nil }
        let tokens = TokenBreakdown(input: usage.int(2), output: usage.int(3), cacheRead: usage.int(5))
        return (tokens, root.string(19))
    }

    static func stepTime(_ data: Data) -> Date? {
        guard let seconds = ProtobufMessage(data)?.message(1)?.varint(1), seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    /// Antigravity holds these databases open in WAL mode. Even a read-only SQLite connection can
    /// create or update the `-shm` file beside the original, which would modify another tool's
    /// directory, so queries run against a private copy of the database and its WAL.
    private func withSnapshot<T>(of database: URL, _ body: (OpaquePointer) -> T) -> T? {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("TokenBar-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: directory) }
        let copy = directory.appendingPathComponent("conversation.db")
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try manager.copyItem(at: database, to: copy)
            let wal = URL(fileURLWithPath: database.path + "-wal")
            if manager.fileExists(atPath: wal.path) { try manager.copyItem(at: wal, to: URL(fileURLWithPath: copy.path + "-wal")) }
        } catch { return nil }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else { return nil }
        return body(db)
    }

    private func rows(_ db: OpaquePointer, _ sql: String) -> [Data] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        var result: [Data] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let count = Int(sqlite3_column_bytes(statement, 0))
            guard count > 0, let bytes = sqlite3_column_blob(statement, 0) else { result.append(Data()); continue }
            result.append(Data(bytes: bytes, count: count))
        }
        return result
    }
}

/// Minimal schemaless protobuf wire-format reader. Only varint and length-delimited fields are
/// retained; any malformed or truncated input yields nil rather than partial data.
struct ProtobufMessage {
    private var varints: [Int: UInt64] = [:]
    private var lengthDelimited: [Int: Data] = [:]

    init?(_ data: Data) {
        let bytes = [UInt8](data)
        var index = 0
        while index < bytes.count {
            guard let key = Self.varint(bytes, &index) else { return nil }
            let field = Int(key >> 3)
            switch key & 7 {
            case 0:
                guard let value = Self.varint(bytes, &index) else { return nil }
                if varints[field] == nil { varints[field] = value }
            case 1: index += 8
            case 2:
                guard let length = Self.varint(bytes, &index), length <= UInt64(bytes.count - index) else { return nil }
                let end = index + Int(length)
                if lengthDelimited[field] == nil { lengthDelimited[field] = Data(bytes[index..<end]) }
                index = end
            case 5: index += 4
            default: return nil
            }
            guard index <= bytes.count, field > 0 else { return nil }
        }
    }

    func varint(_ field: Int) -> UInt64? { varints[field] }
    func int(_ field: Int) -> Int { varints[field].map { Int(clamping: $0) } ?? 0 }
    func message(_ field: Int) -> ProtobufMessage? { lengthDelimited[field].flatMap(ProtobufMessage.init) }
    func string(_ field: Int) -> String? {
        lengthDelimited[field].flatMap { String(data: $0, encoding: .utf8) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func varint(_ bytes: [UInt8], _ index: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count, shift < 64 {
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        return nil
    }
}
