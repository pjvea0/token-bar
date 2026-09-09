import Foundation

actor UsageService {
    private let scanner = TranscriptScanner()

    func collect(enabled: Set<ProviderID>) async -> [ProviderUsage] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var values: [ProviderUsage] = []
        if enabled.contains(.claude) {
            let claudeHome = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) } ?? home.appendingPathComponent(".claude")
            let root = claudeHome.appendingPathComponent("projects")
            let local = scanner.scan(provider: .claude, root: root)
            values.append(await ClaudeLimitCollector().enrich(local, credentialsURL: claudeHome.appendingPathComponent(".credentials.json")))
        }
        if enabled.contains(.codex) {
            let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) } ?? home.appendingPathComponent(".codex")
            let roots = [codexHome.appendingPathComponent("sessions"), codexHome.appendingPathComponent("archived_sessions")]
            values.append(CodexLimitCollector().enrich(scanner.scan(provider: .codex, roots: roots)))
        }
        return values
    }
}
