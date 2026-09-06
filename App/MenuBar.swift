import SwiftUI

/// Contents of the menu bar menu.
struct MenuBarContentView: View {
    let openSettings: @MainActor () -> Void
    let openDebugPreview: @MainActor () -> Void
    let checkForUpdates: @MainActor () -> Void

    var body: some View {
        Button(L("menu.settings", "Settings…")) {
            openSettings()
        }
        .keyboardShortcut(",")

        Button(L("menu.checkForUpdates", "Check for Updates…")) {
            checkForUpdates()
        }

        Button(L("menu.debugPreview", "Debug Preview")) {
            openDebugPreview()
        }
        .keyboardShortcut("d")

        Divider()

        Button(L("menu.quit", "Quit MyNotch")) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
