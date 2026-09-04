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

    func testComingBackWithinTheGracePeriodKeepsTheCardOpen() async throws {
        let model = makeModel()
        model.closeDelay = 0.1
        model.hoverChanged(true)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(model.state.isExpanded)

        model.hoverChanged(false)
        try await Task.sleep(for: .milliseconds(30))
        model.hoverChanged(true)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(model.state.isExpanded, "a brief excursion must not close the card")
    }

    func testACursorRestingInTheGraceZoneGetsOneGracePeriodOnly() async throws {
        let model = makeModel()
        model.closeDelay = 0.15
        model.graceRect = CGRect(x: 0, y: 0, width: 100, height: 100)
        model.cursorLocation = { CGPoint(x: 50, y: 50) }
        model.hoverChanged(true)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(model.state.isExpanded)

        model.hoverChanged(false)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertTrue(model.state.isExpanded, "hovering just outside the card is not leaving yet")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(model.state, .closed, "but the grace period is not renewed")
    }

    func testLeavingTheGraceZoneClosesAtOnce() async throws {
        let model = makeModel()
        model.closeDelay = 1.0
        model.graceRect = CGRect(x: 0, y: 0, width: 100, height: 100)
        var cursor = CGPoint(x: 50, y: 50)
        model.cursorLocation = { cursor }
        model.hoverChanged(true)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(model.state.isExpanded)

        model.hoverChanged(false)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertTrue(model.state.isExpanded)
        cursor = CGPoint(x: 500, y: 500)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(model.state, .closed, "leaving the zone must not wait for the deadline")
    }

    func testLeavingStraightPastTheGraceZoneClosesImmediately() async throws {
        let model = makeModel()
        model.closeDelay = 1.0
        model.graceRect = CGRect(x: 0, y: 0, width: 100, height: 100)
        model.cursorLocation = { CGPoint(x: 500, y: 500) }
        model.hoverChanged(true)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(model.state.isExpanded)

        model.hoverChanged(false)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(model.state, .closed)
    }

    func testTheGraceZoneOnlyMattersWhileExpanded() async throws {
        let model = makeModel()
        model.graceRect = CGRect(x: 0, y: 0, width: 100, height: 100)
        model.cursorLocation = { CGPoint(x: 50, y: 50) }
        model.hoverDelay = 0.1
        model.hoverChanged(true)
        model.hoverChanged(false)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(model.state, .closed, "leaving before expansion cancels it regardless of the zone")
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
