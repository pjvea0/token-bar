import AppKit
import Combine
import Foundation

enum MenuBarDisplayStyle: String, CaseIterable, Identifiable, Sendable {
    case iconOnly
    case provider
    case session
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iconOnly: "Icon only"
        case .provider: "Provider"
        case .session: "Session usage"
        case .weekly: "Weekly usage"
        }
    }

    func label(provider: ProviderID?, limits: [RateLimit]) -> String {
        guard self != .iconOnly, let provider else { return "" }
        let abbreviation = provider == .claude ? "Cl" : "Cx"
        guard self != .provider else { return abbreviation }
        let limit = limits.first { limit in
            let label = limit.label.lowercased()
            return switch self {
            case .session: label.contains("session") || label.contains("5h") || label.contains("5-hour")
            case .weekly: label.contains("weekly") || label.contains("7-day")
            case .iconOnly, .provider: false
            }
        }
        guard let limit else { return abbreviation }
        return "\(abbreviation) \(Int((limit.usedFraction * 100).rounded()))%"
    }
}

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
    @Published var menuBarStyle: MenuBarDisplayStyle = .provider {
        didSet { defaults.set(menuBarStyle.rawValue, forKey: Keys.menuBarStyle) }
    }
    private let service = UsageService()
    private let defaults: UserDefaults
    private var started = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Keys.selected), let provider = ProviderID(rawValue: raw) { selected = provider }
        if defaults.object(forKey: Keys.refreshMinutes) != nil { refreshMinutes = max(1, defaults.integer(forKey: Keys.refreshMinutes)) }
        if defaults.object(forKey: Keys.claudeEnabled) != nil { claudeEnabled = defaults.bool(forKey: Keys.claudeEnabled) }
        if defaults.object(forKey: Keys.codexEnabled) != nil { codexEnabled = defaults.bool(forKey: Keys.codexEnabled) }
        if let raw = defaults.string(forKey: Keys.menuBarStyle), let style = MenuBarDisplayStyle(rawValue: raw) { menuBarStyle = style }
    }

    var current: ProviderUsage? { usages.first { $0.id == selected } ?? usages.first }
    var menuLabel: String {
        menuBarStyle.label(provider: current?.id, limits: current?.limits ?? [])
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
        static let menuBarStyle = "menuBarStyle"
    }
}
