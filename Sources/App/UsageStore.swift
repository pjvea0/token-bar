import AppKit
import Combine
import Foundation

enum MenuBarDisplayStyle: String, CaseIterable, Identifiable, Sendable {
    case iconOnly
    case provider
    case session
    case weekly

    var id: String { rawValue }
    static let initial: Self = .iconOnly

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
        let window: LimitWindow = self == .session ? .session : .weekly
        let limit = limits.first { $0.window == window }
        guard let limit else { return abbreviation }
        return "\(abbreviation) \(Int((limit.usedFraction * 100).rounded()))%"
    }
}

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }
    static let initial: Self = .system

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
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
    @Published var menuBarStyle: MenuBarDisplayStyle = .initial {
        didSet { defaults.set(menuBarStyle.rawValue, forKey: Keys.menuBarStyle) }
    }
    @Published var globalShortcut: GlobalShortcut = .standard {
        didSet {
            if let data = try? JSONEncoder().encode(globalShortcut) { defaults.set(data, forKey: Keys.globalShortcut) }
        }
    }
    @Published var appearance: AppAppearance = .initial {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    @Published var alertRules: [AlertRule] = AlertRule.defaults {
        didSet {
            if let data = try? JSONEncoder().encode(alertRules) { defaults.set(data, forKey: Keys.alertRules) }
            if alertRules.contains(where: \.enabled), !oldValue.contains(where: \.enabled) {
                Task { await requestNotificationPermission() }
            }
        }
    }
    @Published var notificationsDenied = false
    private var firedAlerts: Set<String> = [] {
        didSet { defaults.set(Array(firedAlerts), forKey: Keys.firedAlerts) }
    }
    private let notifier = UsageNotifier()
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
        if let data = defaults.data(forKey: Keys.globalShortcut),
           let shortcut = try? JSONDecoder().decode(GlobalShortcut.self, from: data) { globalShortcut = shortcut }
        if let raw = defaults.string(forKey: Keys.appearance),
           let savedAppearance = AppAppearance(rawValue: raw) { appearance = savedAppearance }
        if let data = defaults.data(forKey: Keys.alertRules),
           let saved = try? JSONDecoder().decode([AlertRule].self, from: data) {
            // Keep any rule added in a later version at its default.
            alertRules = AlertRule.defaults.map { rule in saved.first { $0.id == rule.id } ?? rule }
        }
        firedAlerts = Set(defaults.stringArray(forKey: Keys.firedAlerts) ?? [])
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
        evaluateAlerts()
        isRefreshing = false
    }

    func sendTestNotification() async {
        guard await requestNotificationPermission() else { return }
        notifier.sendTest()
    }

    @discardableResult
    private func requestNotificationPermission() async -> Bool {
        let granted = await notifier.requestAuthorization()
        notificationsDenied = !granted
        return granted
    }

    private func evaluateAlerts() {
        guard alertRules.contains(where: \.enabled) else { return }
        let result = LimitAlertEvaluator.evaluate(usages: usages, rules: alertRules, fired: firedAlerts)
        firedAlerts = result.fired
        result.alerts.forEach(notifier.deliver)
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
        static let globalShortcut = "globalShortcut"
        static let appearance = "appearance"
        static let alertRules = "alertRules"
        static let firedAlerts = "firedAlertKeys"
    }
}
