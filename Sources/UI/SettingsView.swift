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
            Section("Privacy") {
                Text("TokenBar reads local CLI transcripts. Claude credentials are read only to request account limits directly from Anthropic; credentials are never stored by TokenBar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).frame(width: 440, height: 330).padding()
    }
}
