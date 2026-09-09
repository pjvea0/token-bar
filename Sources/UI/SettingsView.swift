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
                LabeledContent("Open TokenBar", value: "⌃⇧⌘R")
                LabeledContent("Claude Code tab", value: "1")
                LabeledContent("Codex tab", value: "2")
                Text(store.globalShortcutAvailable
                     ? "The open shortcut works globally. Number shortcuts work while the panel is open."
                     : "The shortcut could not be registered, usually because another app is already using it.")
                    .font(.caption)
                    .foregroundStyle(store.globalShortcutAvailable ? Color.secondary : Color.red)
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
        }.formStyle(.grouped).frame(width: 440, height: 650).padding()
    }
}
