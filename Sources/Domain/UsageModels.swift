import Foundation

enum ProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude
    case codex

    var id: String { rawValue }
    var displayName: String { self == .claude ? "Claude Code" : "Codex" }
    var command: String { rawValue }
}

struct TokenBreakdown: Codable, Equatable, Sendable {
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0

    var total: Int { input + output + cacheRead + cacheWrite }

    mutating func add(_ other: Self) {
        input += other.input
        output += other.output
        cacheRead += other.cacheRead
        cacheWrite += other.cacheWrite
    }
}

struct DayUsage: Codable, Identifiable, Equatable, Sendable {
    let date: Date
    var tokens: Int
    var prompts: Int
    var sessions: Int
    var id: Date { date }
}

struct ModelUsage: Codable, Identifiable, Equatable, Sendable {
    let name: String
    var tokens: TokenBreakdown
    var id: String { name }
}

struct RateLimit: Codable, Identifiable, Equatable, Sendable {
    let label: String
    let usedFraction: Double
    let resetsAt: Date?
    var id: String { label }
}

struct ProviderUsage: Codable, Identifiable, Equatable, Sendable {
    let id: ProviderID
    var plan: String
    var limits: [RateLimit]
    var days: [DayUsage]
    var models: [ModelUsage]
    var totalPrompts: Int
    var totalSessions: Int
    var activeDays: Int
    var updatedAt: Date
    var status: String?
    var help: String?

    var totalTokens: Int { models.reduce(0) { $0 + $1.tokens.total } }
    var hasUsage: Bool { totalTokens > 0 || !limits.isEmpty }
}
