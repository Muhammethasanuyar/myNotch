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

    func testABannerGrowsTheCardInsteadOfCoveringIt() {
        let plain = NotchLayout.shapeSize(for: .expanded(moduleID: "media"), metrics: notched)
        let withBanner = NotchLayout.shapeSize(for: .expanded(moduleID: "media"), metrics: notched, showsBanner: true)
        XCTAssertEqual(withBanner.width, plain.width)
        XCTAssertEqual(withBanner.height, plain.height + NotchLayout.bannerHeight)
    }

    func testOnlyTheExpandedStateReservesBannerSpace() {
        for state in [NotchState.closed, .compact, .popup(sampleEvent)] {
            XCTAssertEqual(
                NotchLayout.shapeSize(for: state, metrics: notched, showsBanner: true),
                NotchLayout.shapeSize(for: state, metrics: notched),
                "\(state) draws its own surface; a banner belongs to the expanded card"
            )
        }
    }

    func testTheExpandedCardWithABannerStillFitsThePanel() {
        for metrics in [notched, floating] {
            let size = NotchLayout.shapeSize(for: .expanded(moduleID: "media"), metrics: metrics, showsBanner: true)
            XCTAssertLessThanOrEqual(size.height + NotchLayout.topInset(for: metrics), metrics.panelSize.height)
        }
    }

    func testTheScreenSwitcherGrowsTheCardAndStacksWithABanner() {
        let plain = NotchLayout.shapeSize(for: .expanded(moduleID: "media"), metrics: notched)
        let withSwitcher = NotchLayout.shapeSize(for: .expanded(moduleID: "media"), metrics: notched, showsSwitcher: true)
        XCTAssertEqual(withSwitcher.width, plain.width)
        XCTAssertEqual(withSwitcher.height, plain.height + NotchLayout.switcherHeight)

        let both = NotchLayout.shapeSize(for: .expanded(moduleID: "media"), metrics: notched, showsBanner: true, showsSwitcher: true)
        XCTAssertEqual(both.height, plain.height + NotchLayout.bannerHeight + NotchLayout.switcherHeight)
    }

    func testOnlyTheExpandedStateReservesSwitcherSpace() {
        for state in [NotchState.closed, .compact, .popup(sampleEvent)] {
            XCTAssertEqual(
                NotchLayout.shapeSize(for: state, metrics: notched, showsSwitcher: true),
                NotchLayout.shapeSize(for: state, metrics: notched),
                "\(state) has no switcher; it belongs to the expanded card"
            )
        }
    }

    func testTheTallestExpandedCardStillFitsThePanel() {
        for metrics in [notched, floating] {
            let size = NotchLayout.shapeSize(for: .expanded(moduleID: "media"), metrics: metrics, showsBanner: true, showsSwitcher: true)
            XCTAssertLessThanOrEqual(size.height + NotchLayout.topInset(for: metrics), metrics.panelSize.height,
                                     "a card with both strips must leave room for its shadow")
        }
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

    func testGraceZoneSurroundsTheExpandedCardUpToTheScreenEdge() {
        let metrics = notched
        let panel = CGRect(x: 100, y: 800, width: 600, height: 240)
        let card = NotchLayout.shapeSize(for: .expanded(moduleID: "m"), metrics: metrics, showsBanner: true, showsSwitcher: true)
        let zone = NotchLayout.graceRect(panelFrame: panel, metrics: metrics)

        XCTAssertEqual(zone.midX, panel.midX, accuracy: 0.001)
        XCTAssertEqual(zone.width, card.width + 2 * NotchLayout.graceMargin.width, accuracy: 0.001)
        XCTAssertEqual(zone.maxY, panel.maxY + NotchLayout.graceMargin.height, accuracy: 0.001, "reaches past the screen edge")
        XCTAssertEqual(zone.minY, panel.maxY - card.height - NotchLayout.graceMargin.height, accuracy: 0.001)
        XCTAssertTrue(zone.contains(CGPoint(x: panel.midX, y: panel.maxY - card.height + 1)),
                      "the zone must cover the card at its tallest, switcher included")
    }

    func testFloatingGraceZoneCoversTheMenuBarGap() {
        let metrics = floating
        let panel = CGRect(x: 100, y: 800, width: 600, height: 240)
        let card = NotchLayout.shapeSize(for: .expanded(moduleID: "m"), metrics: metrics, showsBanner: true, showsSwitcher: true)
        let zone = NotchLayout.graceRect(panelFrame: panel, metrics: metrics)

        XCTAssertEqual(zone.maxY, panel.maxY + NotchLayout.graceMargin.height, accuracy: 0.001)
        XCTAssertEqual(zone.minY, panel.maxY - NotchLayout.topInset(for: metrics) - card.height - NotchLayout.graceMargin.height, accuracy: 0.001)
    }
}
