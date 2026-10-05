import Foundation

actor UsageService {
    private let scanner = TranscriptScanner()
    private let historyStore: HistoryStore

    init(historyStore: HistoryStore = HistoryStore()) {
        self.historyStore = historyStore
    }

    func collect(enabled: Set<ProviderID>) async -> [ProviderUsage] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var values: [ProviderUsage] = []
        if enabled.contains(.claude) {
            let claudeHome = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) } ?? home.appendingPathComponent(".claude")
            let root = claudeHome.appendingPathComponent("projects")
            let local = scanner.scanWithHistory(provider: .claude, roots: [root])
            historyStore.recordDaily(provider: .claude, daily: local.daily)
            let usage = await ClaudeLimitCollector().enrich(local.usage, credentialsURL: claudeHome.appendingPathComponent(".credentials.json"))
            historyStore.recordLimits(provider: .claude, limits: usage.limits)
            values.append(usage)
        }
        if enabled.contains(.codex) {
            let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) } ?? home.appendingPathComponent(".codex")
            let roots = [codexHome.appendingPathComponent("sessions"), codexHome.appendingPathComponent("archived_sessions")]
            let local = scanner.scanWithHistory(provider: .codex, roots: roots)
            historyStore.recordDaily(provider: .codex, daily: local.daily)
            let usage = CodexLimitCollector().enrich(local.usage)
            historyStore.recordLimits(provider: .codex, limits: usage.limits)
            values.append(usage)
        }
        return values
    }

    func history(provider: ProviderID, start: Date, end: Date) -> UsageHistory {
        historyStore.history(provider: provider, start: start, end: end)
    }

    func clearHistory() {
        historyStore.clear()
    }
}
