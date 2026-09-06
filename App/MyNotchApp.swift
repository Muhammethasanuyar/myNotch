import SwiftUI

@main
struct MyNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Settings live in an AppKit window (`SettingsWindowController`), not a SwiftUI scene: the
        // window's style mask has to be set at creation for the system's translucent chrome.
        MenuBarExtra("MyNotch", systemImage: "sparkles") {
            MenuBarContentView(
                openSettings: appDelegate.showSettings,
                openDebugPreview: appDelegate.showDebugPreview,
                checkForUpdates: appDelegate.checkForUpdates
            )
        }
        .menuBarExtraStyle(.menu)
    }
}
