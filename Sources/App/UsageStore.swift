import AppKit
import Combine
import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published var usages: [ProviderUsage] = []
    @Published var selected: ProviderID = .claude { didSet { defaults.set(selected.rawValue, forKey: Keys.selected) } }
    @Published var isRefreshing = false
    @Published var lastError: String?
    @Published var refreshMinutes = 15 { didSet { defaults.set(refreshMinutes, forKey: Keys.refreshMinutes) } }
    @Published var claudeEnabled = true { didSet { defaults.set(claudeEnabled, forKey: Keys.claudeEnabled) } }
    @Published var codexEnabled = true { didSet { defaults.set(codexEnabled, forKey: Keys.codexEnabled) } }
    @Published var globalShortcutAvailable = true
    private let service = UsageService()
    private let defaults: UserDefaults
    private var started = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Keys.selected), let provider = ProviderID(rawValue: raw) { selected = provider }
        if defaults.object(forKey: Keys.refreshMinutes) != nil { refreshMinutes = max(1, defaults.integer(forKey: Keys.refreshMinutes)) }
        if defaults.object(forKey: Keys.claudeEnabled) != nil { claudeEnabled = defaults.bool(forKey: Keys.claudeEnabled) }
        if defaults.object(forKey: Keys.codexEnabled) != nil { codexEnabled = defaults.bool(forKey: Keys.codexEnabled) }
    }

    var current: ProviderUsage? { usages.first { $0.id == selected } ?? usages.first }
    var menuLabel: String {
        guard let current else { return "AI Usage" }
        let percent = current.limits.first.map { " \(Int($0.usedFraction * 100))%" } ?? ""
        return "\(current.id == .claude ? "Cl" : "Cx")\(percent)"
    }

    func start() async {
        guard !started else { return }
        started = true
        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(max(60, refreshMinutes * 60)))
            await refresh()
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let enabled = Set(ProviderID.allCases.filter { $0 == .claude ? claudeEnabled : codexEnabled })
        usages = await service.collect(enabled: enabled)
        if !usages.contains(where: { $0.id == selected }), let first = usages.first { selected = first.id }
        isRefreshing = false
    }

    func launch(_ provider: ProviderID) {
        let script = "tell application \"Terminal\" to do script \"\(provider.command)\""
        if let appleScript = NSAppleScript(source: script) { var error: NSDictionary?; appleScript.executeAndReturnError(&error) }
    }

    private enum Keys {
        static let selected = "selectedProvider"
        static let refreshMinutes = "refreshMinutes"
        static let claudeEnabled = "claudeEnabled"
        static let codexEnabled = "codexEnabled"
    }
}
