import AppKit

/// Application lifecycle: owns the notch view model, the notch panel and the Debug Preview window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = NotchViewModel()
    private var notchWindowController: NotchWindowController?
    private var debugPreviewWindowController: DebugPreviewWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let options = LaunchOptions.read(from: .standard)

        // Phase 1 has no module system yet, so the engine renders the Debug Preview's fake content.
        let notchController = NotchWindowController(
            model: model,
            content: FakeNotchContent.provider(),
            debugTint: options.debugTintNotch,
            collapsesOnOutsideClick: options.debugState == nil
        )
        notchController.show()
        notchWindowController = notchController

        model.setLiveContent(options.hasLiveContent)
        if let stateName = options.debugState {
            applyDebugState(named: stateName)
        }
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
        let controller = debugPreviewWindowController ?? DebugPreviewWindowController(metrics: metrics, liveModel: model)
        debugPreviewWindowController = controller
        controller.show(metrics: metrics)
    }

    private func applyDebugState(named name: String) {
        switch name {
        case "closed":
            model.override(.closed)
        case "compact":
            model.override(.compact)
        case "expanded":
            model.override(.expanded(moduleID: FakeNotchContent.moduleID))
        case "popup":
            model.showPopup(FakeNotchContent.sampleEvent(duration: 30))
        default:
            assertionFailure("Unknown -debugState value: \(name)")
        }
    }
}
