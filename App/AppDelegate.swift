import AppKit

/// Application lifecycle: owns the notch view model, the module system, the notch panel and the
/// Debug Preview window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = NotchViewModel()
    private var moduleManager: ModuleManager?
    private var notchWindowController: NotchWindowController?
    private var debugPreviewWindowController: DebugPreviewWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let options = LaunchOptions.read(from: .standard)

        let manager = ModuleManager(model: model)
        manager.register(MediaModule())
        // The demo module only exists to exercise the engine, so it never ships in a release build.
        let demo = DemoModule()
        #if DEBUG
        manager.register(demo)
        #endif
        moduleManager = manager

        let notchController = NotchWindowController(
            model: model,
            content: manager.contentProvider(),
            debugTint: options.debugTintNotch,
            collapsesOnOutsideClick: options.debugState == nil
        )
        notchController.show()
        notchWindowController = notchController

        if options.hasLiveContent {
            demo.setActivity(.live)
        }
        if let stateName = options.debugState {
            applyDebugState(named: stateName, demo: demo)
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
        guard let metrics = notchWindowController?.metrics, let moduleManager else {
            assertionFailure("showDebugPreview() called before the notch window exists")
            return
        }
        let controller = debugPreviewWindowController
            ?? DebugPreviewWindowController(metrics: metrics, liveModel: model, manager: moduleManager)
        debugPreviewWindowController = controller
        controller.show(metrics: metrics)
    }

    /// `-debugState <name>`: forces a state at launch so it can be screenshotted.
    private func applyDebugState(named name: String, demo: DemoModule) {
        switch name {
        case "closed":
            demo.setActivity(.idle)
            model.override(.closed)
        case "compact":
            demo.setActivity(.live)
            model.override(.compact)
        case "expanded":
            demo.setActivity(.live)
            model.override(.expanded(moduleID: demo.id))
        case "popup":
            demo.setActivity(.live)
            model.showPopup(
                NotchEvent(
                    moduleID: demo.id,
                    title: "Now playing",
                    detail: "\(demo.track.artist) — \(demo.track.title)",
                    symbolName: "music.note",
                    duration: 30
                )
            )
        default:
            assertionFailure("Unknown -debugState value: \(name)")
        }
    }
}
