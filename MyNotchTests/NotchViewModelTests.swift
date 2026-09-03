import XCTest
@testable import MyNotch

@MainActor
final class NotchViewModelTests: XCTestCase {
    private func makeModel() -> NotchViewModel {
        let model = NotchViewModel()
        model.hapticsEnabled = false
        model.hoverDelay = 0.01
        model.closeDelay = 0.01
        return model
    }

    func testStartsClosedAndFollowsLiveContent() {
        let model = makeModel()
        XCTAssertEqual(model.state, .closed)
        model.setLiveContent(true)
        XCTAssertEqual(model.state, .compact)
        model.setLiveContent(false)
        XCTAssertEqual(model.state, .closed)
    }

    func testExpandAndCollapseReturnToRestingState() {
        let model = makeModel()
        model.setLiveContent(true)
        model.expand()
        XCTAssertEqual(model.state, .expanded(moduleID: "debug"))
        // Live content changing while expanded must not yank the surface closed.
        model.setLiveContent(false)
        XCTAssertEqual(model.state, .expanded(moduleID: "debug"))
        model.collapse()
        XCTAssertEqual(model.state, .closed)
    }

    func testPopupWhileExpandedShowsBanner() {
        let model = makeModel()
        model.expand(moduleID: "media")
        let event = NotchEvent(moduleID: "claude", title: "Block at 80%", duration: 10)
        model.showPopup(event)
        XCTAssertEqual(model.state, .expanded(moduleID: "media"))
        XCTAssertEqual(model.banner, event)
        model.collapse()
        XCTAssertNil(model.banner)
    }

    func testOverrideSetsStateAndLiveContent() {
        let model = makeModel()
        model.override(.compact)
        XCTAssertEqual(model.state, .compact)
        XCTAssertTrue(model.hasLiveContent)
        model.override(.closed)
        XCTAssertEqual(model.state, .closed)
        XCTAssertFalse(model.hasLiveContent)
    }

    func testPopupExpiresBackToRestingState() async throws {
        let model = makeModel()
        model.setLiveContent(true)
        model.showPopup(NotchEvent(moduleID: "media", title: "Track", duration: 0.05))
        XCTAssertTrue(model.state.isPopup)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(model.state, .compact)
    }

    func testHoverExpandsAfterDelayAndCollapsesAfterExit() async throws {
        let model = makeModel()
        model.hoverChanged(true)
        XCTAssertEqual(model.state, .closed, "must wait for the hover delay")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.state, .expanded(moduleID: "debug"))
        model.hoverChanged(false)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.state, .closed)
    }

    func testLeavingBeforeTheDelayCancelsExpansion() async throws {
        let model = makeModel()
        model.hoverDelay = 0.1
        model.hoverChanged(true)
        model.hoverChanged(false)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(model.state, .closed)
    }
}
