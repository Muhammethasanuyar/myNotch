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
        // Registered first: with nothing live, hovering the notch opens whoever comes first, and
        // the usage dashboard is worth a look at any time while an idle player is not.
        manager.register(ClaudeUsageModule())
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

        // `-liveContent YES` / `-demoLive YES`: makes the demo module live so the engine can be
        // exercised without a real player running.
        if options.hasLiveContent || options.demoLive {
            demo.setActivity(.live)
        }
        if let stateName = options.debugState {
            applyDebugState(named: stateName, moduleID: options.debugModule, demo: demo)
        }
        if options.debugBanner {
            // From the demo module, so it lands as a banner inside whatever module is expanded.
            manager.bus.post(.popup(NotchEvent(
                moduleID: demo.id,
                title: "Claude block at 80%",
                detail: "Another module interrupting",
                symbolName: "bell.fill",
                duration: 60
            )))
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

    /// `-debugState <name>`: forces a state at launch so it can be screenshotted;
    /// `-debugModule <id>` picks the module the expanded state opens.
    private func applyDebugState(named name: String, moduleID: String?, demo: DemoModule) {
        switch name {
        case "closed":
            model.override(.closed)
        case "compact":
            model.override(.compact)
        case "expanded":
            // Whoever owns the notch (with a player running, the media module) unless told otherwise.
            model.override(.expanded(moduleID: moduleID ?? model.defaultModuleID))
        case "popup":
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
