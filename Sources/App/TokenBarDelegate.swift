import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
final class TokenBarDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let store = UsageStore()

    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var hotKey: GlobalHotKey?
    private var keyboardMonitor: Any?
    private var refreshTask: Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configurePopover()
        observeMenuLabel()
        observeGlobalShortcut()
        registerGlobalShortcut(store.globalShortcut)
        registerPanelShortcuts()
        refreshTask = Task { await store.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.highlight(true)
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem?.button?.highlight(false)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }
        button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "TokenBar")
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(togglePopover)
        statusItem = item
        updateMenuLabel()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: UsagePanel(store: store))
    }

    private func observeMenuLabel() {
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                DispatchQueue.main.async { self?.updateMenuLabel() }
            }
            .store(in: &subscriptions)
    }

    private func updateMenuLabel() {
        statusItem?.button?.title = store.menuLabel
    }

    private func observeGlobalShortcut() {
        store.$globalShortcut
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] shortcut in self?.registerGlobalShortcut(shortcut) }
            .store(in: &subscriptions)
    }

    private func registerGlobalShortcut(_ shortcut: GlobalShortcut) {
        hotKey = nil
        hotKey = GlobalHotKey(shortcut: shortcut) { [weak self] in
            Task { @MainActor in self?.togglePopover() }
        }
        store.globalShortcutAvailable = hotKey != nil
    }

    private func registerPanelShortcuts() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover.isShown,
                  event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return event }
            let provider: ProviderID?
            switch event.charactersIgnoringModifiers {
            case "1": provider = .claude
            case "2": provider = .codex
            default: provider = nil
            }
            guard let provider, self.store.usages.contains(where: { $0.id == provider }) else { return event }
            self.store.selected = provider
            return nil
        }
    }
}
