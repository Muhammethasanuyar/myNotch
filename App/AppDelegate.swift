import AppKit

/// Application lifecycle: owns the notch panel and the developer-facing Debug Preview window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchWindowController: NotchWindowController?
    private var debugPreviewWindowController: DebugPreviewWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let options = LaunchOptions.read(from: .standard)

        let notchController = NotchWindowController(debugTint: options.debugTintNotch)
        notchController.show()
        notchWindowController = notchController

        if options.openDebugPreview {
            showDebugPreview()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Opens (or brings forward) the Debug Preview window with the current notch metrics.
    func showDebugPreview() {
        guard let metrics = notchWindowController?.metrics else {
            assertionFailure("showDebugPreview() called before the notch window exists")
            return
        }
        let controller = debugPreviewWindowController ?? DebugPreviewWindowController(metrics: metrics)
        debugPreviewWindowController = controller
        controller.show(metrics: metrics)
    }
}
