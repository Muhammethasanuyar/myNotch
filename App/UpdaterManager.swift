import AppKit
import Observation
import Sparkle

/// Sparkle's standard updater, wrapped so nothing else imports Sparkle. It only ever reads the
/// appcast in this repository (`SUFeedURL`), once a day when the switch in Settings → General is
/// on, and offers a new version — it never installs one without asking.
///
/// A menu-bar app has no window for Sparkle to attach its scheduled alert to, so scheduled finds
/// are handled "gently": the menu bar item reads "Update to x.y.z…" until the user looks, and the
/// standard Sparkle window only opens when they ask (that item, or Check for Updates…). Sparkle
/// logs a warning about background apps without exactly this behaviour.
///
/// Started only in Release builds: a Debug build runs out of DerivedData, signed ad hoc for this
/// machine, and would only find a "newer" release it cannot sensibly install over itself.
@MainActor
@Observable
final class UpdaterManager: NSObject, SPUStandardUserDriverDelegate {
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    private(set) var isStarted = false
    /// The version a scheduled check found and the user has not looked at yet.
    private(set) var pendingVersion: String?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
    }

    /// Whether Sparkle checks the appcast on its own schedule (`SUScheduledCheckInterval`). Set
    /// before `start()`, so Sparkle never shows its own "check automatically?" question.
    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    func start() {
        #if !DEBUG
        controller?.startUpdater()
        isStarted = true
        #endif
    }

    /// The menu item. The app has no Dock icon to click, so it activates itself first or the
    /// update window would open behind whatever the user is doing.
    func checkForUpdates() {
        guard isStarted, let controller else { return }
        NSApplication.shared.activate()
        controller.checkForUpdates(nil)
    }

    // MARK: SPUStandardUserDriverDelegate — gentle scheduled reminders

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        // In focus (the user is looking at us) Sparkle may show its window; otherwise we remind gently.
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate else { return }
        let version = update.displayVersionString
        Task { @MainActor in self.pendingVersion = version }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        Task { @MainActor in self.pendingVersion = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in self.pendingVersion = nil }
    }
}
