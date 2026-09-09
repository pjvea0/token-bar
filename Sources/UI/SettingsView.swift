import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: UsageStore
    var body: some View {
        Form {
            Section("Providers") {
                Toggle("Claude Code", isOn: $store.claudeEnabled)
                Toggle("Codex", isOn: $store.codexEnabled)
            }
            Section("Refresh") {
                Stepper("Every \(store.refreshMinutes) minutes", value: $store.refreshMinutes, in: 1...60)
                Button("Refresh Now") { Task { await store.refresh() } }
            }
            Section("Appearance") {
                Picker("Color scheme", selection: $store.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                Text("System follows the current macOS appearance. Light and Dark override it for TokenBar only.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Menu Bar") {
                Picker("Display", selection: $store.menuBarStyle) {
                    ForEach(MenuBarDisplayStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                LabeledContent("Current value", value: store.menuLabel.isEmpty ? "Icon only" : store.menuLabel)
                Text("Session and weekly values update whenever TokenBar refreshes. If that limit is unavailable, the provider abbreviation is shown.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Keyboard") {
                LabeledContent("Open TokenBar") {
                    HStack(spacing: 6) {
                        ShortcutRecorderButton(shortcut: $store.globalShortcut)
                        if store.globalShortcut != .standard {
                            Button { store.globalShortcut = .standard } label: {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("Restore default shortcut")
                        }
                    }
                }
                LabeledContent("Claude Code tab", value: "1")
                LabeledContent("Codex tab", value: "2")
                Text("Click the shortcut to record a new modified key. Number shortcuts work while the panel is open.")
                    .font(.caption).foregroundStyle(.secondary)
                if !store.globalShortcutAvailable {
                    Label("This shortcut is already in use. Record a different combination.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.red)
                }
            }
            Section("Agents") {
                Button { store.launch(.claude) } label: {
                    Label("Open Claude Code in Terminal", systemImage: "terminal")
                }
                Button { store.launch(.codex) } label: {
                    Label("Open Codex in Terminal", systemImage: "terminal")
                }
                Text("Agent launch actions open a new command in Terminal.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Privacy") {
                Text("TokenBar reads local CLI transcripts. Claude credentials are read only to request account limits directly from Anthropic; credentials are never stored by TokenBar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 650)
        .padding()
    }
}

private struct ShortcutRecorderButton: View {
    @Binding var shortcut: GlobalShortcut
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(isRecording ? "Press shortcut…" : shortcut.displayText) {
            isRecording ? stopRecording() : startRecording()
        }
        .buttonStyle(.bordered)
        .monospaced()
        .help("Record global shortcut")
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            let modifiers = carbonModifiers(event.modifierFlags)
            guard modifiers != 0, let key = displayKey(for: event) else {
                NSSound.beep()
                return nil
            }
            shortcut = GlobalShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    private func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    private func displayKey(for event: NSEvent) -> String? {
        let specialKeys: [UInt16: String] = [
            UInt16(kVK_Space): "Space", UInt16(kVK_Return): "↩", UInt16(kVK_Tab): "⇥",
            UInt16(kVK_Delete): "⌫", UInt16(kVK_ForwardDelete): "⌦",
            UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
            UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
            UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3",
            UInt16(kVK_F4): "F4", UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
            UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8", UInt16(kVK_F9): "F9",
            UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12"
        ]
        if let special = specialKeys[event.keyCode] { return special }
        guard let characters = event.charactersIgnoringModifiers?.uppercased(),
              characters.count == 1 else { return nil }
        return characters
    }
}
