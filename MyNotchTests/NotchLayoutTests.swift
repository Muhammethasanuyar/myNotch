import XCTest
@testable import MyNotch

final class NotchLayoutTests: XCTestCase {
    private let notched = NotchLayoutMetrics(
        screenName: "Built-in",
        style: .notch,
        notchSize: CGSize(width: 168, height: 37),
        menuBarHeight: 37,
        panelSize: NotchLayout.expandedPanelSize
    )

    private var floating: NotchLayoutMetrics { notched.asFloating() }

    private let sampleEvent = NotchEvent(moduleID: "debug", title: "Test")

    func testClosedShapeMatchesHousing() {
        XCTAssertEqual(NotchLayout.shapeSize(for: .closed, metrics: notched), CGSize(width: 168, height: 37))
        XCTAssertEqual(NotchLayout.cornerRadii(for: .closed, style: .notch), .init(ear: 0, bottom: 10, top: 0))
    }

    func testCompactAddsWingsAndEars() {
        let wing = NotchLayout.compactWingWidth(notchHeight: 37)
        XCTAssertEqual(wing, 35)
        let size = NotchLayout.shapeSize(for: .compact, metrics: notched)
        XCTAssertEqual(size, CGSize(width: 168 + 2 * 35 + 2 * 6, height: 37))
    }

    func testCompactWingHasMinimumWidth() {
        XCTAssertEqual(NotchLayout.compactWingWidth(notchHeight: 20), 24)
    }

    func testPopupGrowsAroundHousing() {
        let size = NotchLayout.shapeSize(for: .popup(sampleEvent), metrics: notched)
        XCTAssertEqual(size, CGSize(width: 168 + 240 + 16, height: 37 + 16))
    }

    func testExpandedIncludesHousingAndEars() {
        let size = NotchLayout.shapeSize(for: .expanded(moduleID: "debug"), metrics: notched)
        XCTAssertEqual(size, CGSize(width: 420 + 30, height: 37 + 150))
        XCTAssertEqual(NotchLayout.expandedTopInset(for: notched), 37)
    }

    func testEveryStateFitsInsideThePanel() {
        let states: [NotchState] = [.closed, .compact, .popup(sampleEvent), .expanded(moduleID: "debug")]
        for metrics in [notched, floating] {
            for state in states {
                let size = NotchLayout.shapeSize(for: state, metrics: metrics)
                let inset = NotchLayout.topInset(for: metrics)
                XCTAssertLessThanOrEqual(size.width, metrics.panelSize.width, "\(state) too wide for \(metrics.style)")
                XCTAssertLessThanOrEqual(size.height + inset, metrics.panelSize.height, "\(state) too tall for \(metrics.style)")
            }
        }
    }

    func testFloatingClosedRendersNothing() {
        XCTAssertEqual(NotchLayout.shapeSize(for: .closed, metrics: floating), .zero)
    }

    func testFloatingSitsBelowMenuBar() {
        XCTAssertEqual(NotchLayout.topInset(for: notched), 0)
        XCTAssertEqual(NotchLayout.topInset(for: floating), 37 + NotchLayout.floatingTopGap)
        XCTAssertEqual(NotchLayout.expandedTopInset(for: floating), NotchLayout.expandedContentInset)
    }

    func testFloatingCompactIsACapsule() {
        let radii = NotchLayout.cornerRadii(for: .compact, style: .floating)
        XCTAssertEqual(radii.ear, 0)
        XCTAssertEqual(radii.top, NotchLayout.floatingCompactSize.height / 2)
        XCTAssertEqual(radii.bottom, radii.top)
        XCTAssertEqual(NotchLayout.shapeSize(for: .compact, metrics: floating), NotchLayout.floatingCompactSize)
    }
}
