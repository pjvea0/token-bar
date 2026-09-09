import SwiftUI

@main
struct TokenBarApp: App {
    @NSApplicationDelegateAdaptor(TokenBarDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(store: appDelegate.store)
        }
    }
}
