import Foundation

struct TranscriptScanner: Sendable {
    private let decoder = JSONDecoder()
    private let calendar = Calendar.current

    func scan(provider: ProviderID, root: URL, now: Date = .now) -> ProviderUsage {
        scan(provider: provider, roots: [root], now: now)
    }

    func scan(provider: ProviderID, roots: [URL], now: Date = .now) -> ProviderUsage {
        scanWithHistory(provider: provider, roots: roots, now: now).usage
    }

    /// Also returns per-day, per-model totals for every retained event. Unlike the summary
    /// usage, the daily history ignores Codex's rolling 30-day window so it can be archived.
    func scanWithHistory(provider: ProviderID, roots: [URL], now: Date = .now) -> (usage: ProviderUsage, daily: [Date: DailyTotals]) {
        let historyStart = provider == .codex ? calendar.date(byAdding: .day, value: -30, to: now) : nil
        var accumulator = UsageAccumulator(calendar: calendar, now: now, summaryStart: historyStart)
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
                guard var event = parse(value, provider: provider, file: file, defaultModel: currentModel) else { continue }
                if event.id == nil { event.id = "\(file.path):\(rawLine.hashValue)" }
                accumulator.add(event)
            }
        }

        let historyScope: UsageHistoryScope = provider == .codex ? .rollingDays(30) : .allLocalHistory
        return accumulator.finish(provider: provider, scope: historyScope)
    }

    private func parse(_ entry: JSONValue, provider: ProviderID, file: URL, defaultModel: String) -> UsageEvent? {
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
        return UsageEvent(id: message["id"]?.string ?? entry["uuid"]?.string,
                          session: entry["sessionId"]?.string ?? file.path,
                          model: message["model"]?.string ?? entry["model"]?.string ?? defaultModel,
                          date: date, tokens: tokens)
    }

    private func int(_ value: JSONValue?) -> Int { Int(value?.number ?? 0) }
}

/// One model response's token usage, normalized from any provider's local records.
struct UsageEvent: Sendable {
    /// Deduplication key; events sharing an ID are counted once.
    var id: String?
    let session: String
    let model: String
    let date: Date
    let tokens: TokenBreakdown
}

/// Folds usage events into the panel summary and the per-day history every scanner returns.
struct UsageAccumulator {
    let calendar: Calendar
    let now: Date
    /// Events before this date are kept in daily history but excluded from the summary.
    let summaryStart: Date?
    private var seen = Set<String>()
    private var sessionDays: [String: Set<Date>] = [:]
    private var days: [Date: (tokens: Int, prompts: Int)] = [:]
    private var models: [String: TokenBreakdown] = [:]
    private var daily: [Date: DailyTotals] = [:]
    private var dailySessions: [Date: Set<String>] = [:]

    init(calendar: Calendar = .current, now: Date, summaryStart: Date? = nil) {
        self.calendar = calendar
        self.now = now
        self.summaryStart = summaryStart
    }

    mutating func add(_ event: UsageEvent) {
        if let id = event.id { guard seen.insert(id).inserted else { return } }
        guard event.date <= now else { return }
        let day = calendar.startOfDay(for: event.date)
        daily[day, default: DailyTotals()].models[event.model, default: ModelDayTotals()].tokens.add(event.tokens)
        daily[day, default: DailyTotals()].models[event.model, default: ModelDayTotals()].prompts += 1
        dailySessions[day, default: []].insert(event.session)
        guard summaryStart.map({ event.date >= $0 }) ?? true else { return }
        days[day, default: (0, 0)].tokens += event.tokens.total
        days[day, default: (0, 0)].prompts += 1
        sessionDays[event.session, default: []].insert(day)
        models[event.model, default: .init()].add(event.tokens)
    }

    func finish(provider: ProviderID, scope: UsageHistoryScope) -> (usage: ProviderUsage, daily: [Date: DailyTotals]) {
        let start = calendar.startOfDay(for: now)
        let recent = (-6...0).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }.map { day in
            let value = days[day] ?? (0, 0)
            return DayUsage(date: day, tokens: value.tokens, prompts: value.prompts,
                            sessions: sessionDays.values.filter { $0.contains(day) }.count)
        }
        var daily = daily
        for (day, sessions) in dailySessions { daily[day]?.sessions = sessions.count }
        let usage = ProviderUsage(
            id: provider, plan: "", limits: [], days: recent,
            models: models.map { ModelUsage(name: $0.key, tokens: $0.value) }.sorted { $0.tokens.total > $1.tokens.total },
            historyScope: scope,
            totalPrompts: days.values.reduce(0) { $0 + $1.prompts }, totalSessions: sessionDays.count,
            activeDays: days.count, updatedAt: now, status: nil, help: nil
        )
        return (usage, daily)
    }
}
