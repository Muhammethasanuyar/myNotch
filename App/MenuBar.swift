import SwiftUI

/// Contents of the menu bar menu.
struct MenuBarContentView: View {
    let openDebugPreview: @MainActor () -> Void

    var body: some View {
        Button("Debug Preview") {
            openDebugPreview()
        }
        .keyboardShortcut("d")

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit MyNotch") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
