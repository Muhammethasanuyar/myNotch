import XCTest
@testable import MyNotch

@MainActor
final class SettingsStoreTests: XCTestCase {
    private func isolatedDefaults() -> UserDefaults {
        let suite = "SettingsStoreTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }

    func testFreshStoreShipsWithTheEngineDefaults() {
        let store = SettingsStore(defaults: isolatedDefaults())

        XCTAssertEqual(store.hoverDelay, 0.15)
        XCTAssertEqual(store.closeDelay, 0.8)
        XCTAssertTrue(store.hapticsEnabled)
        XCTAssertEqual(store.displaySelection, .automatic)
        XCTAssertTrue(store.lyricsEnabled)
        XCTAssertEqual(store.lyricsLeadSeconds, 0.15)
        XCTAssertEqual(store.spotifyClientID, "")
        XCTAssertEqual(store.usageWarningThreshold, 0.80)
        XCTAssertEqual(store.usageCriticalThreshold, 0.95)
        XCTAssertEqual(store.usagePollInterval, 300)
        XCTAssertTrue(store.usageAlertsEnabled)
        XCTAssertFalse(store.onboardingCompleted)
        XCTAssertTrue(store.isModuleEnabled("media"))
    }

    func testKeysMatchWhatTheEarlierPhasesReadDirectly() {
        // Modules keep reading these on their own; renaming a key here would silently split them.
        XCTAssertEqual(SettingsKey.spotifyClientID.rawValue, SpotifyLibraryClient.clientIDKey)
        XCTAssertEqual(SettingsKey.lyricsShifts.rawValue, LyricsService.shiftsKey)
        XCTAssertEqual(SettingsKey.ccusagePath.rawValue, CCUsageRunner.pathOverrideKey)
        XCTAssertEqual(SettingsKey.lyricsEnabled.rawValue, "lyricsEnabled")
        XCTAssertEqual(SettingsKey.lyricsLeadSeconds.rawValue, "lyricsLeadSeconds")
        XCTAssertEqual(SettingsKey.claudeConfigDir.rawValue, "claudeConfigDir")
    }

    func testValuesSurviveANewStoreOverTheSameDefaults() {
        let defaults = isolatedDefaults()
        let first = SettingsStore(defaults: defaults)
        first.hoverDelay = 0.3
        first.closeDelay = 0.5
        first.hapticsEnabled = false
        first.displaySelection = .named("Studio Display")
        first.lyricsLeadSeconds = -0.2
        first.spotifyClientID = " abc123 "
        first.usageWarningThreshold = 0.7
        first.usageCriticalThreshold = 0.9
        first.usagePollInterval = 900
        first.usageAlertsEnabled = false
        first.ccusagePath = "/opt/homebrew/bin/ccusage"
        first.claudeConfigDir = "~/.claude-work"
        first.onboardingCompleted = true
        first.setModule("demo", enabled: false)

        let second = SettingsStore(defaults: defaults)
        XCTAssertEqual(second.hoverDelay, 0.3)
        XCTAssertEqual(second.closeDelay, 0.5)
        XCTAssertFalse(second.hapticsEnabled)
        XCTAssertEqual(second.displaySelection, .named("Studio Display"))
        XCTAssertEqual(second.lyricsLeadSeconds, -0.2)
        XCTAssertEqual(second.spotifyClientID, "abc123", "stored trimmed, the way the Spotify client reads it")
        XCTAssertEqual(second.usageWarningThreshold, 0.7)
        XCTAssertEqual(second.usageCriticalThreshold, 0.9)
        XCTAssertEqual(second.usagePollInterval, 900)
        XCTAssertFalse(second.usageAlertsEnabled)
        XCTAssertEqual(second.ccusagePath, "/opt/homebrew/bin/ccusage")
        XCTAssertEqual(second.claudeConfigDir, "~/.claude-work")
        XCTAssertTrue(second.onboardingCompleted)
        XCTAssertFalse(second.isModuleEnabled("demo"))
        XCTAssertTrue(second.isModuleEnabled("media"))
    }

    func testEmptyTextRemovesTheKeyInsteadOfStoringBlanks() {
        let defaults = isolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        store.spotifyClientID = "abc"
        store.spotifyClientID = "   "

        XCTAssertNil(defaults.object(forKey: SettingsKey.spotifyClientID.rawValue))
    }

    func testOutOfRangeValuesAreClampedOnWriteAndOnRead() {
        let defaults = isolatedDefaults()
        defaults.set(5.0, forKey: SettingsKey.closeDelay.rawValue)
        defaults.set(0.0, forKey: SettingsKey.hoverDelay.rawValue)
        defaults.set(42.0, forKey: SettingsKey.usagePollInterval.rawValue)
        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.closeDelay, 1.0, "the grace period never exceeds a second")
        XCTAssertEqual(store.hoverDelay, 0.05)
        XCTAssertEqual(store.usagePollInterval, 300, "never below the endpoint's floor")

        store.closeDelay = 3
        XCTAssertEqual(store.closeDelay, 1.0)
        XCTAssertEqual(defaults.double(forKey: SettingsKey.closeDelay.rawValue), 1.0)
        store.usagePollInterval = 700
        XCTAssertEqual(store.usagePollInterval, 600, "snaps to the nearest offered interval")
    }

    func testCriticalThresholdStaysAboveWarning() {
        let store = SettingsStore(defaults: isolatedDefaults())

        store.usageWarningThreshold = 0.95
        XCTAssertEqual(store.usageWarningThreshold, 0.95)
        XCTAssertEqual(store.usageCriticalThreshold, 1.0)

        store.usageCriticalThreshold = 0.6
        XCTAssertEqual(store.usageCriticalThreshold, 1.0, "critical cannot drop under warning + gap")

        store.resetThresholds()
        XCTAssertEqual(store.usageWarningThreshold, 0.80)
        XCTAssertEqual(store.usageCriticalThreshold, 0.95)
    }

    func testChangesAnnounceTheirKeyOnce() {
        let store = SettingsStore(defaults: isolatedDefaults())
        var seen: [SettingsKey] = []
        store.onChange = { seen.append($0) }

        store.hoverDelay = 0.2
        store.setModule("media", enabled: false)
        store.setModule("media", enabled: false)
        store.usageWarningThreshold = 0.9
        store.resetLyricsShifts()

        XCTAssertEqual(seen, [.hoverDelay, .disabledModules, .usageWarningThreshold, .lyricsShifts])
    }

    func testResetEngineDefaultsRestoresTheShippedValues() {
        let store = SettingsStore(defaults: isolatedDefaults())
        store.hoverDelay = 0.4
        store.closeDelay = 0.2
        store.hapticsEnabled = false
        store.displaySelection = .named("LG")

        store.resetEngineDefaults()

        XCTAssertEqual(store.hoverDelay, 0.15)
        XCTAssertEqual(store.closeDelay, 0.8)
        XCTAssertTrue(store.hapticsEnabled)
        XCTAssertEqual(store.displaySelection, .automatic)
    }

    func testRulesAreStable() {
        let low = SettingsRules.thresholds(warning: 0.3, critical: 0.2)
        XCTAssertEqual(low.warning, 0.5)
        XCTAssertEqual(low.critical, 0.55)
        let shipped = SettingsRules.thresholds(warning: 0.8, critical: 0.95)
        XCTAssertEqual(shipped.warning, 0.8)
        XCTAssertEqual(shipped.critical, 0.95)
        XCTAssertEqual(SettingsRules.pollInterval(1_000_000), 1800)
        XCTAssertEqual(SettingsRules.pollInterval(449), 300)
        XCTAssertEqual(SettingsRules.pollInterval(451), 600)
    }
}
