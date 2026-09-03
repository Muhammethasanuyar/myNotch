import XCTest
@testable import MyNotch

final class NotchTransitionTests: XCTestCase {
    private let event = NotchEvent(moduleID: "media", title: "Track changed")
    private let otherEvent = NotchEvent(moduleID: "claude", title: "Block at 80%")

    func testRestingStateFollowsLiveContent() {
        XCTAssertEqual(NotchTransition.restingState(hasLiveContent: false), .closed)
        XCTAssertEqual(NotchTransition.restingState(hasLiveContent: true), .compact)
    }

    func testPopupInterruptsRestingStates() {
        for current in [NotchState.closed, .compact] {
            let resolution = NotchTransition.applyPopup(event, to: current)
            XCTAssertEqual(resolution.state, .popup(event))
            XCTAssertNil(resolution.banner)
        }
    }

    func testPopupReplacesAnotherPopup() {
        let resolution = NotchTransition.applyPopup(otherEvent, to: .popup(event))
        XCTAssertEqual(resolution.state, .popup(otherEvent))
        XCTAssertNil(resolution.banner)
    }

    func testPopupBecomesBannerWhileExpanded() {
        let expanded = NotchState.expanded(moduleID: "media")
        let resolution = NotchTransition.applyPopup(event, to: expanded)
        XCTAssertEqual(resolution.state, expanded)
        XCTAssertEqual(resolution.banner, event)
    }

    func testHoverExpandsFromRestingStatesIntoDefaultModule() {
        XCTAssertEqual(NotchTransition.stateOnHoverExpand(from: .closed, defaultModuleID: "media"), .expanded(moduleID: "media"))
        XCTAssertEqual(NotchTransition.stateOnHoverExpand(from: .compact, defaultModuleID: "media"), .expanded(moduleID: "media"))
    }

    func testHoverExpandsAPopupIntoItsOwnModule() {
        XCTAssertEqual(NotchTransition.stateOnHoverExpand(from: .popup(otherEvent), defaultModuleID: "media"), .expanded(moduleID: "claude"))
    }

    func testHoverDoesNothingWhenAlreadyExpanded() {
        XCTAssertNil(NotchTransition.stateOnHoverExpand(from: .expanded(moduleID: "media"), defaultModuleID: "media"))
    }

    func testHoverExitCollapsesOnlyExpanded() {
        XCTAssertEqual(NotchTransition.stateOnHoverExit(from: .expanded(moduleID: "media"), hasLiveContent: true), .compact)
        XCTAssertEqual(NotchTransition.stateOnHoverExit(from: .expanded(moduleID: "media"), hasLiveContent: false), .closed)
        XCTAssertNil(NotchTransition.stateOnHoverExit(from: .compact, hasLiveContent: true))
        XCTAssertNil(NotchTransition.stateOnHoverExit(from: .popup(event), hasLiveContent: true))
    }
}
