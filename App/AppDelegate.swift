import AppKit

/// Application lifecycle: owns the notch view model, the module system, the notch panel, the
/// settings window and the Debug Preview window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = NotchViewModel()
    private let settings = SettingsStore()
    private let updater = UpdaterManager()
    private let launchAtLogin = LaunchAtLogin()
    private var moduleManager: ModuleManager?
    private var terminationSignal: DispatchSourceSignal?
    private var settingsApplier: SettingsApplier?
    private var notchWindowController: NotchWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var debugPreviewWindowController: DebugPreviewWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        routeTerminationSignalThroughQuit()
        let options = LaunchOptions.read(from: .standard)

        let manager = ModuleManager(model: model)
        // Registered first: with nothing live, hovering the notch opens whoever comes first, and
        // the usage dashboard is worth a look at any time while an idle player is not.
        register(ClaudeUsageModule(), in: manager)
        register(MediaModule(), in: manager)
        register(CalendarModule(), in: manager)
        register(PomodoroModule(), in: manager)
        register(BatteryModule(), in: manager)
        register(ShelfModule(), in: manager)
        // The demo module only exists to exercise the engine, so it never ships in a release build.
        let demo = DemoModule()
        #if DEBUG
        register(demo, in: manager)
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

        let applier = SettingsApplier(store: settings, model: model, manager: manager, notch: notchController, updater: updater)
        applier.applyAll()
        settings.onChange = { applier.apply($0) }
        settingsApplier = applier
        // After the settings, so Sparkle starts with the user's answer to "check automatically?"
        // already in place and never asks it itself. No-op in Debug builds.
        updater.start()

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
        if let tabName = options.openSettings {
            showSettings(tab: SettingsTab(rawValue: tabName) ?? .general)
        } else if !settings.onboardingCompleted, options.debugState == nil {
            // First launch: the checklist of permissions and sign-ins, until the user says Done.
            showSettings(tab: .setup)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// A module the user switched off stays off across launches: the flag is set before
    /// registration so `register` never starts it.
    private func register(_ module: any NotchModule, in manager: ModuleManager) {
        module.isEnabled = settings.isModuleEnabled(module.id)
        manager.register(module)
    }

    /// Menu bar "Check for Updates…".
    func checkForUpdates() {
        updater.checkForUpdates()
    }

    /// Menu bar "Settings…": opens (or brings forward) the settings window where it was left.
    func showSettings() {
        showSettings(tab: nil)
    }

    func showSettings(tab: SettingsTab?) {
        guard let moduleManager else {
            assertionFailure("showSettings() called before the modules exist")
            return
        }
        let controller = settingsWindowController ?? SettingsWindowController(context: SettingsContext(
            store: settings,
            manager: moduleManager,
            launchAtLogin: launchAtLogin,
            openDebugPreview: { [weak self] in self?.showDebugPreview() },
            checkForUpdates: { [weak self] in self?.checkForUpdates() }
        ))
        settingsWindowController = controller
        controller.show(tab: tab)
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
            // `-debugModule <id>` renders the event with that module's popup view (the media
            // module's, say); the title is long on purpose, so a layout that hides text shows it.
            model.showPopup(
                NotchEvent(
                    moduleID: moduleID ?? demo.id,
                    title: "A Rather Long Track Title That Must Stay Readable Beside The Housing",
                    detail: "\(demo.track.artist) — \(demo.track.title)",
                    symbolName: "music.note",
                    duration: 30
                )
            )
        default:
            assertionFailure("Unknown -debugState value: \(name)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        moduleManager?.stopAll()
    }

    /// `kill`/`pkill` send SIGTERM, whose default is an immediate exit that skips
    /// `applicationWillTerminate` — and with it the shutdown of child processes. Routing the signal
    /// through the normal quit path keeps a restart from the shell as clean as Quit from the menu.
    private func routeTerminationSignalThroughQuit() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminationSignal = source
    }
}
