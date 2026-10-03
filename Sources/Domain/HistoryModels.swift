import Foundation

/// One recorded observation of a provider-reported limit.
struct LimitSample: Codable, Equatable, Sendable {
    let date: Date
    let provider: ProviderID
    let label: String
    let window: LimitWindow?
    let usedFraction: Double
    let resetsAt: Date?
}

struct ModelDayTotals: Codable, Equatable, Sendable {
    var tokens = TokenBreakdown()
    var prompts = 0
}

/// Local transcript totals for one calendar day.
struct DailyTotals: Codable, Equatable, Sendable {
    var models: [String: ModelDayTotals] = [:]
    var sessions = 0

    var tokens: Int { models.values.reduce(0) { $0 + $1.tokens.total } }
    var prompts: Int { models.values.reduce(0) { $0 + $1.prompts } }

    /// Field-wise maximum. A day's transcript totals only grow until the CLI prunes old
    /// transcripts, so the maximum preserves recorded history without double-counting rescans.
    func merged(with other: Self) -> Self {
        var result = Self(models: models, sessions: max(sessions, other.sessions))
        for (name, incoming) in other.models {
            let existing = result.models[name] ?? ModelDayTotals()
            result.models[name] = ModelDayTotals(
                tokens: TokenBreakdown(input: max(existing.tokens.input, incoming.tokens.input),
                                       output: max(existing.tokens.output, incoming.tokens.output),
                                       cacheRead: max(existing.tokens.cacheRead, incoming.tokens.cacheRead),
                                       cacheWrite: max(existing.tokens.cacheWrite, incoming.tokens.cacheWrite)),
                prompts: max(existing.prompts, incoming.prompts))
        }
        return result
    }
}

struct HistoryDay: Identifiable, Equatable, Sendable {
    let date: Date
    let totals: DailyTotals
    var id: Date { date }
}

struct UsageHistory: Equatable, Sendable {
    let provider: ProviderID
    let start: Date
    let end: Date
    /// One entry per calendar day in the range, including zero-use days.
    let days: [HistoryDay]
    let samples: [LimitSample]
    let earliestRecord: Date?

    var totalTokens: Int { days.reduce(0) { $0 + $1.totals.tokens } }
    var totalPrompts: Int { days.reduce(0) { $0 + $1.totals.prompts } }
    var activeDays: Int { days.filter { $0.totals.tokens > 0 }.count }
    var isEmpty: Bool { activeDays == 0 && samples.isEmpty }
}
