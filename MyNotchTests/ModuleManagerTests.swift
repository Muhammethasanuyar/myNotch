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

    func expandedView(namespace: Namespace.ID) -> AnyView {
        AnyView(Text(id))
    }
}

@MainActor
final class ModuleManagerTests: XCTestCase {
    private func makeManager() -> (ModuleManager, NotchViewModel) {
        let model = NotchViewModel()
        model.hapticsEnabled = false
        return (ModuleManager(model: model), model)
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
}
