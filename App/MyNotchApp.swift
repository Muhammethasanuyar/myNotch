import SwiftUI

@main
struct MyNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("MyNotch", systemImage: "sparkles") {
            MenuBarContentView(openDebugPreview: appDelegate.showDebugPreview)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}
