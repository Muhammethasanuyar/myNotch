import AppKit
import Sparkle

/// Sparkle's standard updater, wrapped so nothing else imports Sparkle. It only ever reads the
/// appcast in this repository (`SUFeedURL`), once a day when the switch in Settings → General is
/// on, and offers a new version — it never installs one without asking.
///
/// Started only in Release builds: a Debug build runs out of DerivedData, signed ad hoc for this
/// machine, and would only find a "newer" release it cannot sensibly install over itself.
@MainActor
final class UpdaterManager {
    private let controller: SPUStandardUpdaterController
    private(set) var isStarted = false

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    }

    /// Whether Sparkle checks the appcast on its own schedule (`SUScheduledCheckInterval`). Set
    /// before `start()`, so Sparkle never shows its own "check automatically?" question.
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func start() {
        #if !DEBUG
        controller.startUpdater()
        isStarted = true
        #endif
    }

    /// The menu item. The app has no Dock icon to click, so it activates itself first or the
    /// update window would open behind whatever the user is doing.
    func checkForUpdates() {
        guard isStarted else { return }
        NSApplication.shared.activate()
        controller.checkForUpdates(nil)
    }
}
