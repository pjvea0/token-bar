import Foundation

struct TranscriptScanner: Sendable {
    private let decoder = JSONDecoder()
    private let calendar = Calendar.current

    func scan(provider: ProviderID, root: URL, now: Date = .now) -> ProviderUsage {
        scan(provider: provider, roots: [root], now: now)
    }

    func scan(provider: ProviderID, roots: [URL], now: Date = .now) -> ProviderUsage {
        let historyScope: UsageHistoryScope = provider == .codex ? .rollingDays(30) : .allLocalHistory
        let historyStart = provider == .codex ? calendar.date(byAdding: .day, value: -30, to: now) : nil
        var seen = Set<String>()
        var sessionDays: [String: Set<Date>] = [:]
        var days: [Date: (tokens: Int, prompts: Int)] = [:]
        var models: [String: TokenBreakdown] = [:]
        let files = roots.flatMap { root in
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])?
                .compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" } ?? []
        }

        for file in files {
            var currentModel = provider.rawValue
            guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? handle.close() }
            for rawLine in handle.readDataToEndOfFile().split(separator: 0x0A) {
                guard (provider == .codex || rawLine.range(of: Data("usage".utf8)) != nil),
                      let value = try? decoder.decode(JSONValue.self, from: rawLine) else { continue }
                if provider == .codex, value["type"]?.string == "turn_context" {
                    currentModel = value["payload"]?["model"]?.string ?? value["payload"]?["model_slug"]?.string ?? currentModel
                    continue
                }
                guard let event = parse(value, provider: provider, file: file, defaultModel: currentModel) else { continue }
                let unique = event.messageID ?? "\(file.path):\(rawLine.hashValue)"
                guard seen.insert(unique).inserted else { continue }
                guard event.date <= now, historyStart.map({ event.date >= $0 }) ?? true else { continue }
                let day = calendar.startOfDay(for: event.date)
                days[day, default: (0, 0)].tokens += event.tokens.total
                days[day, default: (0, 0)].prompts += 1
                sessionDays[event.session, default: []].insert(day)
                models[event.model, default: .init()].add(event.tokens)
            }
        }

        let start = calendar.startOfDay(for: now)
        let recent = (-6...0).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }.map { day in
            let value = days[day] ?? (0, 0)
            return DayUsage(date: day, tokens: value.tokens, prompts: value.prompts,
                            sessions: sessionDays.values.filter { $0.contains(day) }.count)
        }
        return ProviderUsage(
            id: provider, plan: "", limits: [], days: recent,
            models: models.map { ModelUsage(name: $0.key, tokens: $0.value) }.sorted { $0.tokens.total > $1.tokens.total },
            historyScope: historyScope,
            totalPrompts: days.values.reduce(0) { $0 + $1.prompts }, totalSessions: sessionDays.count,
            activeDays: days.count, updatedAt: now, status: nil, help: nil
        )
    }

    private struct Event {
        let messageID: String?
        let session: String
        let model: String
        let date: Date
        let tokens: TokenBreakdown
    }

    private func parse(_ entry: JSONValue, provider: ProviderID, file: URL, defaultModel: String) -> Event? {
        let message = entry["message"] ?? entry
        let payload = entry["payload"]?["payload"] ?? entry["payload"] ?? entry
        let source = provider == .claude ? message : payload
        guard let usage = source["usage"] ?? source["info"]?["last_token_usage"] else { return nil }
        if provider == .claude {
            let role = message["role"]?.string
            guard entry["type"]?.string == "assistant" || role == "assistant" else { return nil }
        } else {
            guard payload["type"]?.string == "token_count" else { return nil }
        }
        let cached = int(usage["cache_read_input_tokens"] ?? usage["cached_input_tokens"] ?? usage["cacheRead"])
        let created = int(usage["cache_creation_input_tokens"] ?? usage["cache_write_input_tokens"] ?? usage["cacheWrite"])
        let rawInput = int(usage["input_tokens"] ?? usage["inputTokens"] ?? usage["input"])
        let tokens = TokenBreakdown(input: provider == .codex ? max(0, rawInput - cached - created) : rawInput,
                                    output: int(usage["output_tokens"] ?? usage["outputTokens"] ?? usage["output"]),
                                    cacheRead: cached, cacheWrite: created)
        guard tokens.total > 0 else { return nil }
        let rawDate = entry["timestamp"]?.string ?? message["timestamp"]?.string
        let date = rawDate.flatMap(ISO8601DateFormatter().date) ?? (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
        return Event(messageID: message["id"]?.string ?? entry["uuid"]?.string,
                     session: entry["sessionId"]?.string ?? file.path,
                     model: message["model"]?.string ?? entry["model"]?.string ?? defaultModel,
                     date: date, tokens: tokens)
    }

    private func int(_ value: JSONValue?) -> Int { Int(value?.number ?? 0) }
}
