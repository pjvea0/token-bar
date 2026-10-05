import Foundation

enum ProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude
    case codex
    case gemini

    var id: String { rawValue }
    var command: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .gemini: "Gemini"
        }
    }

    var abbreviation: String {
        switch self {
        case .claude: "Cl"
        case .codex: "Cx"
        case .gemini: "Gm"
        }
    }

    /// Gemini CLI and Antigravity expose no supported quota interface, so Gemini is local-only.
    var reportsLimits: Bool { self != .gemini }
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

enum UsageHistoryScope: Codable, Equatable, Sendable {
    case allLocalHistory
    case rollingDays(Int)

    var title: String {
        switch self {
        case .allLocalHistory: "All local history"
        case .rollingDays(let days): "Last \(days) days"
        }
    }

}

struct RateLimit: Codable, Identifiable, Equatable, Sendable {
    let label: String
    let usedFraction: Double
    let resetsAt: Date?
    var id: String { label }
}

/// A remediation the UI can offer next to a provider status message.
enum StatusAction: String, Codable, Sendable {
    case openCLI
}

struct ProviderUsage: Codable, Identifiable, Equatable, Sendable {
    let id: ProviderID
    var plan: String
    var limits: [RateLimit]
    var days: [DayUsage]
    var models: [ModelUsage]
    var historyScope: UsageHistoryScope
    var totalPrompts: Int
    var totalSessions: Int
    var activeDays: Int
    var updatedAt: Date
    var status: String?
    var help: String?
    var action: StatusAction? = nil

    var totalTokens: Int { models.reduce(0) { $0 + $1.tokens.total } }
    var hasUsage: Bool { totalTokens > 0 || !limits.isEmpty }
}

enum LimitWindow: String, Codable, CaseIterable, Identifiable, Sendable {
    case session
    case weekly

    var id: String { rawValue }
    var title: String { self == .session ? "Session" : "Weekly" }
}

extension RateLimit {
    /// Provider-agnostic classification of the general session and weekly allowances.
    /// Model-scoped weekly limits also classify as weekly; callers that want the general
    /// allowance take the first match, which collectors always list first.
    var window: LimitWindow? {
        let label = label.lowercased()
        if label.contains("session") || label.contains("5h") || label.contains("5-hour") { return .session }
        if label.contains("weekly") || label.contains("7-day") { return .weekly }
        return nil
    }
}

struct AlertRule: Codable, Equatable, Identifiable, Sendable {
    let provider: ProviderID
    let window: LimitWindow
    var enabled: Bool
    var thresholds: [Int]

    var id: String { "\(provider.rawValue).\(window.rawValue)" }

    static let suggestedThresholds = [80, 95]
    static let maximumThresholds = 3

    static var defaults: [AlertRule] {
        ProviderID.allCases.filter(\.reportsLimits).flatMap { provider in
            LimitWindow.allCases.map { AlertRule(provider: provider, window: $0, enabled: false, thresholds: suggestedThresholds) }
        }
    }
}

struct LimitAlert: Equatable, Sendable {
    let provider: ProviderID
    let limit: RateLimit
    let threshold: Int
}

/// Decides which threshold crossings deserve a notification. `fired` holds one key per
/// (provider, limit, threshold, reset cycle) so each crossing alerts once per quota window.
enum LimitAlertEvaluator {
    static func evaluate(usages: [ProviderUsage], rules: [AlertRule], fired: Set<String>,
                         now: Date = .now) -> (alerts: [LimitAlert], fired: Set<String>) {
        var alerts: [LimitAlert] = []
        var nextFired = fired.filter { key in
            guard let reset = key.split(separator: "|").last.flatMap({ Double($0) }), reset > 0 else { return true }
            return Date(timeIntervalSince1970: reset) > now
        }
        for usage in usages {
            for limit in usage.limits {
                guard let window = limit.window,
                      let rule = rules.first(where: { $0.provider == usage.id && $0.window == window }), rule.enabled else { continue }
                let percent = limit.usedFraction * 100
                if limit.resetsAt == nil {
                    // Without a reset time there is no cycle identity; re-arm once usage falls back.
                    rule.thresholds.filter { Double($0) > percent }.forEach { nextFired.remove(key(usage.id, limit, $0)) }
                }
                let crossed = rule.thresholds.filter { Double($0) <= percent + 0.0001 }
                let unfired = crossed.filter { !nextFired.contains(key(usage.id, limit, $0)) }
                guard let highest = unfired.max() else { continue }
                crossed.forEach { nextFired.insert(key(usage.id, limit, $0)) }
                alerts.append(LimitAlert(provider: usage.id, limit: limit, threshold: highest))
            }
        }
        return (alerts, nextFired)
    }

    static func key(_ provider: ProviderID, _ limit: RateLimit, _ threshold: Int) -> String {
        // Providers can report slightly different reset instants between refreshes; ten-minute
        // buckets keep one quota cycle on one key.
        let reset = limit.resetsAt.map { Int(($0.timeIntervalSince1970 / 600).rounded()) * 600 } ?? 0
        return "\(provider.rawValue)|\(limit.label)|\(threshold)|\(reset)"
    }
}
