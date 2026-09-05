import SwiftUI
import XCTest
@testable import MyNotch

/// Minimal module used to drive the manager without any UI.
@MainActor
private final class StubModule: NotchModule {
    let id: String
    let displayName: String
    let priority: Int
    var isEnabled: Bool
    var isAvailable = true
    private(set) var activity: ModuleActivity
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var context: ModuleContext?

    init(id: String, priority: Int = 0, activity: ModuleActivity = .idle, isEnabled: Bool = true) {
        self.id = id
        self.displayName = id.capitalized
        self.priority = priority
        self.activity = activity
        self.isEnabled = isEnabled
    }

    func start(context: ModuleContext) {
        self.context = context
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func setActivity(_ newActivity: ModuleActivity) {
        activity = newActivity
        context?.activityChanged()
    }

    func post(_ event: NotchEvent) {
        context?.post(event)
    }

    private(set) var selectedScreenID: String?

    var screens: [ModuleScreen] {
        [ModuleScreen(id: id, moduleID: id, title: displayName, symbolName: "circle", appBundleIdentifier: "com.example.\(id)", isAvailable: isAvailable)]
    }

    func selectScreen(_ screenID: String) {
        selectedScreenID = screenID
    }

    func expandedView(namespace: Namespace.ID) -> AnyView {
        AnyView(Text(id))
    }
}

@MainActor
final class ModuleManagerTests: XCTestCase {
    private func makeManager(defaults: UserDefaults? = nil) -> (ModuleManager, NotchViewModel) {
        let model = NotchViewModel()
        model.hapticsEnabled = false
        return (ModuleManager(model: model, defaults: defaults ?? isolatedDefaults()), model)
    }

    /// The test host is the app itself, so the real defaults may hold a preference from daily use.
    private func isolatedDefaults() -> UserDefaults {
        let suite = "ModuleManagerTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }

    func testRegisteringStartsEnabledModules() {
        let (manager, _) = makeManager()
        let enabled = StubModule(id: "a")
        let disabled = StubModule(id: "b", isEnabled: false)
        manager.register(enabled)
        manager.register(disabled)

        XCTAssertEqual(enabled.startCount, 1)
        XCTAssertEqual(disabled.startCount, 0)
        XCTAssertEqual(manager.modules.count, 2)
    }

    func testIdleModulesLeaveTheNotchClosed() {
        let (manager, model) = makeManager()
        manager.register(StubModule(id: "a"))

        XCTAssertNil(manager.activeModuleID)
        XCTAssertFalse(model.hasLiveContent)
        XCTAssertEqual(model.state, .closed)
        XCTAssertEqual(model.defaultModuleID, "a", "hover should still have somewhere to go")
    }

    func testLiveModuleTakesTheCompactState() {
        let (manager, model) = makeManager()
        let module = StubModule(id: "media")
        manager.register(module)

        module.setActivity(.live)

        XCTAssertEqual(manager.activeModuleID, "media")
        XCTAssertEqual(model.state, .compact)
        XCTAssertEqual(model.defaultModuleID, "media")
    }

    func testHigherPriorityLiveModuleWinsTheNotch() {
        let (manager, model) = makeManager()
        let low = StubModule(id: "low", priority: 1)
        let high = StubModule(id: "high", priority: 9)
        manager.register(low)
        manager.register(high)

        low.setActivity(.live)
        XCTAssertEqual(manager.activeModuleID, "low")

        high.setActivity(.live)
        XCTAssertEqual(manager.activeModuleID, "high")
        XCTAssertEqual(model.defaultModuleID, "high")
    }

    func testPostedEventBecomesAPopup() {
        let (manager, model) = makeManager()
        let module = StubModule(id: "media")
        manager.register(module)

        let event = NotchEvent(moduleID: "media", title: "Track changed", duration: 30)
        module.post(event)

        XCTAssertEqual(model.state, .popup(event))
    }

    func testEventsFromDisabledModulesAreDropped() {
        let (manager, model) = makeManager()
        let module = StubModule(id: "media")
        manager.register(module)
        manager.setEnabled(false, for: "media")

        module.post(NotchEvent(moduleID: "media", title: "Ignored", duration: 30))

        XCTAssertEqual(model.state, .closed)
        XCTAssertEqual(module.stopCount, 1)
    }

    func testDisablingTheExpandedModuleCollapsesTheNotch() {
        let (manager, model) = makeManager()
        let module = StubModule(id: "media")
        manager.register(module)
        module.setActivity(.live)
        model.expand(moduleID: "media")
        XCTAssertTrue(model.state.isExpanded)

        manager.setEnabled(false, for: "media")

        XCTAssertEqual(model.state, .closed)
        XCTAssertNil(manager.activeModuleID)
    }

    func testReenablingRestartsTheModule() {
        let (manager, _) = makeManager()
        let module = StubModule(id: "media")
        manager.register(module)
        manager.setEnabled(false, for: "media")
        manager.setEnabled(true, for: "media")

        XCTAssertEqual(module.startCount, 2)
        XCTAssertTrue(module.isEnabled)
    }

    func testContentProviderFallsBackOnlyInPreview() {
        let (manager, _) = makeManager()
        manager.register(StubModule(id: "media"))

        // No module is live, so the real notch renders nothing…
        XCTAssertNil(manager.activeModuleID)
        // …while the preview provider still resolves the first enabled module for its expanded view.
        let preview = manager.contentProvider(previewFallback: true)
        XCTAssertNotNil(preview.expanded)
    }

    func testScreensSkipDisabledAndUnavailableModules() {
        let (manager, _) = makeManager()
        let claude = StubModule(id: "claude")
        let media = StubModule(id: "media")
        let off = StubModule(id: "off", isEnabled: false)
        media.isAvailable = false
        manager.register(claude)
        manager.register(media)
        manager.register(off)

        XCTAssertEqual(manager.screens(activeScreenID: "claude").map(\.id), ["claude"])

        media.isAvailable = true
        XCTAssertEqual(manager.screens(activeScreenID: "claude").map(\.id), ["claude", "media"], "a player that just started earns a tab")

        media.isAvailable = false
        XCTAssertEqual(manager.screens(activeScreenID: "media").map(\.id), ["claude", "media"], "the screen on show keeps its tab")
    }

    func testPickingAScreenFocusesItsModuleAndPutsItOnTheCard() {
        let (manager, model) = makeManager()
        let media = StubModule(id: "media")
        manager.register(media)
        manager.register(StubModule(id: "claude"))
        model.expand(moduleID: "claude")

        manager.selectScreen(ModuleScreen(id: "media.music", moduleID: "media", title: "Music", symbolName: "music.note"))

        XCTAssertEqual(media.selectedScreenID, "media.music", "the module decides what its own screen means")
        XCTAssertEqual(model.state, .expanded(moduleID: "media"))
    }

    func testPicksForDisabledModulesAreIgnored() {
        let (manager, model) = makeManager()
        let media = StubModule(id: "media", isEnabled: false)
        manager.register(media)

        manager.selectScreen(ModuleScreen(id: "media", moduleID: "media", title: "Media", symbolName: "circle"))

        XCTAssertNil(media.selectedScreenID)
        XCTAssertEqual(model.state, .closed)
    }

    func testTheContentProviderHandsTheEngineTheSameScreens() {
        let (manager, _) = makeManager()
        manager.register(StubModule(id: "claude"))
        manager.register(StubModule(id: "media"))

        let provider = manager.contentProvider()
        XCTAssertEqual(provider.screens("claude").map(\.id), ["claude", "media"])
        XCTAssertEqual(provider.screens("claude").first?.appBundleIdentifier, "com.example.claude")
    }

    func testHoverReopensTheScreenTheUserChoseEvenWhileAnotherModuleOwnsTheStrip() {
        let (manager, model) = makeManager()
        let claude = StubModule(id: "claude", priority: 5)
        let media = StubModule(id: "media", priority: 10)
        manager.register(claude)
        manager.register(media)
        media.setActivity(.live)
        XCTAssertEqual(model.defaultModuleID, "media", "nothing chosen yet: the owner of the strip")

        manager.selectScreen(ModuleScreen(id: "claude", moduleID: "claude", title: "Claude", symbolName: "asterisk"))
        XCTAssertEqual(model.defaultModuleID, "claude")

        media.setActivity(.idle)
        media.setActivity(.live)
        XCTAssertEqual(manager.activeModuleID, "media", "the compact strip still follows the music")
        XCTAssertEqual(model.defaultModuleID, "claude", "but hovering keeps opening what the user chose")
    }

    func testTheChoiceGivesWayWhenItsScreenIsGone() {
        let (manager, model) = makeManager()
        let claude = StubModule(id: "claude")
        let media = StubModule(id: "media", priority: 10)
        manager.register(claude)
        manager.register(media)
        manager.selectScreen(ModuleScreen(id: "media", moduleID: "media", title: "Spotify", symbolName: "music.note"))
        XCTAssertEqual(model.defaultModuleID, "media")

        media.isAvailable = false
        media.setActivity(.idle)
        XCTAssertEqual(model.defaultModuleID, "claude", "a player that quit cannot be the destination")

        media.isAvailable = true
        media.setActivity(.idle)
        XCTAssertEqual(model.defaultModuleID, "media", "and it comes back with the player")
    }

    func testTheChoiceSurvivesARelaunch() {
        let defaults = isolatedDefaults()
        let (first, _) = makeManager(defaults: defaults)
        first.register(StubModule(id: "claude"))
        first.register(StubModule(id: "media"))
        first.selectScreen(ModuleScreen(id: "media", moduleID: "media", title: "Spotify", symbolName: "music.note"))

        let (second, model) = makeManager(defaults: defaults)
        second.register(StubModule(id: "claude"))
        second.register(StubModule(id: "media"))
        XCTAssertEqual(second.preferredModuleID, "media")
        XCTAssertEqual(model.defaultModuleID, "media")
    }
}
