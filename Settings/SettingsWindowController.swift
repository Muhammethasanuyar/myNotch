import AppKit
import SwiftUI

/// The settings window: an AppKit window, so `.fullSizeContentView` gives the sidebar the
/// system's translucent chrome, hosting the SwiftUI panes. One instance lives as long as the app.
final class SettingsWindowController: NSWindowController {
    private let navigation = SettingsNavigation()

    init(context: SettingsContext) {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L("settings.title", "MyNotch Settings")
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.minSize = CGSize(width: 640, height: 480)
        window.setFrameAutosaveName("SettingsWindow")

        let root = SettingsView(context: context, navigation: navigation, closeWindow: { [weak window] in window?.close() })
        let hosting = NSHostingController(rootView: root)
        // The window keeps its own size; SwiftUI must not shrink it to the panes' minimum.
        hosting.sizingOptions = []
        window.contentViewController = hosting
        // Assigning the controller fits the window to the view's initial size; put ours back.
        window.setContentSize(CGSize(width: 720, height: 560))
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SettingsWindowController does not support NSCoding")
    }

    /// Brings the window forward, on `tab` when one is given. The app is menu-bar-only, so the
    /// window is ordered front regardless of which app is active — a first launch has no click
    /// from the user to ride on.
    func show(tab: SettingsTab? = nil) {
        if let tab {
            navigation.selectedTab = tab
        }
        NSApplication.shared.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
