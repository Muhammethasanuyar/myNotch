import XCTest
@testable import MyNotch

final class NotchGeometryTests: XCTestCase {
    /// Values shaped like a 16" MacBook Pro at default scaling (1728×1117 pt, 37 pt housing).
    private let notchedScreen = ScreenTopGeometry(
        frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        safeAreaTop: 37,
        auxiliaryTopLeft: CGRect(x: 0, y: 1080, width: 780, height: 37),
        auxiliaryTopRight: CGRect(x: 948, y: 1080, width: 780, height: 37)
    )

    /// An external display without a camera housing, arranged left of and below the primary screen.
    private let plainScreen = ScreenTopGeometry(
        frame: CGRect(x: -2560, y: -200, width: 2560, height: 1440),
        safeAreaTop: 0,
        auxiliaryTopLeft: nil,
        auxiliaryTopRight: nil
    )

    func testNotchRectSpansGapBetweenAuxiliaryAreas() {
        XCTAssertEqual(
            NotchGeometry.notchRect(for: notchedScreen),
            CGRect(x: 780, y: 1080, width: 168, height: 37)
        )
    }

    func testNotchRectIsNilWithoutSafeArea() {
        XCTAssertNil(NotchGeometry.notchRect(for: plainScreen))
    }

    func testNotchRectIsNilWhenAuxiliaryAreasMissing() {
        let screen = ScreenTopGeometry(
            frame: notchedScreen.frame,
            safeAreaTop: 37,
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: nil
        )
        XCTAssertNil(NotchGeometry.notchRect(for: screen))
    }

    func testNotchRectUsesGlobalCoordinatesOfOffsetScreen() {
        let offset = ScreenTopGeometry(
            frame: CGRect(x: -1728, y: 300, width: 1728, height: 1117),
            safeAreaTop: 37,
            auxiliaryTopLeft: CGRect(x: -1728, y: 1380, width: 780, height: 37),
            auxiliaryTopRight: CGRect(x: -780, y: 1380, width: 780, height: 37)
        )
        XCTAssertEqual(
            NotchGeometry.notchRect(for: offset),
            CGRect(x: -948, y: 1380, width: 168, height: 37)
        )
    }

    func testNotchRectIsIndependentOfAuxiliaryAreaCoordinateSpace() {
        // Same offset screen, but the auxiliary areas reported relative to the screen's own origin.
        let localCoordinates = ScreenTopGeometry(
            frame: CGRect(x: -1728, y: 300, width: 1728, height: 1117),
            safeAreaTop: 37,
            auxiliaryTopLeft: CGRect(x: 0, y: 1080, width: 780, height: 37),
            auxiliaryTopRight: CGRect(x: 948, y: 1080, width: 780, height: 37)
        )
        XCTAssertEqual(
            NotchGeometry.notchRect(for: localCoordinates),
            CGRect(x: -948, y: 1380, width: 168, height: 37)
        )
    }

    func testPanelFrameIsCentredOnAnchorAndFlushWithScreenTop() {
        let frame = NotchGeometry.panelFrame(
            centeredAt: 864,
            screenFrame: notchedScreen.frame,
            panelSize: CGSize(width: 600, height: 240)
        )
        XCTAssertEqual(frame, CGRect(x: 564, y: 877, width: 600, height: 240))
    }

    func testLayoutPanelFrameCentresOnNotch() {
        let frame = NotchLayout.panelFrame(for: notchedScreen)
        XCTAssertEqual(frame.midX, 864, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, notchedScreen.frame.maxY, accuracy: 0.001)
        XCTAssertEqual(frame.size, NotchLayout.expandedPanelSize)
    }

    func testLayoutPanelFrameCentresOnScreenWithoutNotch() {
        let frame = NotchLayout.panelFrame(for: plainScreen)
        XCTAssertEqual(frame.midX, plainScreen.frame.midX, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, plainScreen.frame.maxY, accuracy: 0.001)
    }

    func testMetricsReportNotchSize() {
        let metrics = NotchLayout.metrics(for: notchedScreen, screenName: "Built-in")
        XCTAssertTrue(metrics.hasNotch)
        XCTAssertEqual(metrics.style, .notch)
        XCTAssertEqual(metrics.notchSize, CGSize(width: 168, height: 37))
        XCTAssertEqual(metrics.panelSize, NotchLayout.expandedPanelSize)
        XCTAssertEqual(metrics.screenName, "Built-in")
    }

    func testMetricsFallBackToFloatingStyleWithoutNotch() {
        let metrics = NotchLayout.metrics(for: plainScreen, screenName: "External")
        XCTAssertFalse(metrics.hasNotch)
        XCTAssertEqual(metrics.style, .floating)
        XCTAssertEqual(metrics.notchSize, NotchLayout.floatingCompactSize)
    }
}
