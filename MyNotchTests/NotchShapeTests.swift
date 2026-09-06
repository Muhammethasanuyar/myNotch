import SwiftUI
import XCTest
@testable import MyNotch

/// The silhouette must be a proper capsule or housing: every corner arc has to join the edge it
/// leads into, or the path cuts across the shape.
final class NotchShapeTests: XCTestCase {
    private let rect = CGRect(x: 0, y: 0, width: 220, height: 36)

    func testFloatingCapsuleKeepsItsCorners() {
        let path = NotchShape(earRadius: 0, bottomRadius: 18, topRadius: 18).path(in: rect)

        // Inside the rounded corners (17 pt from the corner's centre, radius 18)…
        XCTAssertTrue(path.contains(CGPoint(x: 3, y: 10)), "top-left corner is part of the capsule")
        XCTAssertTrue(path.contains(CGPoint(x: 217, y: 10)), "top-right corner is part of the capsule")
        XCTAssertTrue(path.contains(CGPoint(x: 3, y: 26)), "bottom-left corner is part of the capsule")
        // …along the edges…
        XCTAssertTrue(path.contains(CGPoint(x: 110, y: 1)), "the top edge is straight, not slanted")
        XCTAssertTrue(path.contains(CGPoint(x: 1, y: 18)), "the left edge is straight")
        XCTAssertTrue(path.contains(CGPoint(x: 110, y: 18)))
        // …and nothing outside the arcs.
        XCTAssertFalse(path.contains(CGPoint(x: 1, y: 1)))
        XCTAssertFalse(path.contains(CGPoint(x: 219, y: 35)))
        XCTAssertEqual(path.boundingRect, rect)
    }

    func testHousingKeepsItsEarsAndBottomCorners() {
        let path = NotchShape(earRadius: 6, bottomRadius: 14, topRadius: 0).path(in: rect)

        XCTAssertTrue(path.contains(CGPoint(x: 110, y: 1)), "flush with the screen edge")
        XCTAssertTrue(path.contains(CGPoint(x: 8, y: 20)), "inside, past the ear")
        XCTAssertFalse(path.contains(CGPoint(x: 1, y: 5)), "the ear is a concave flare, so this is outside")
        XCTAssertFalse(path.contains(CGPoint(x: 7, y: 35)), "below the bottom-left arc")
        XCTAssertEqual(path.boundingRect, rect)
    }

    func testDegenerateRectsProduceNoPath() {
        XCTAssertTrue(NotchShape(earRadius: 6, bottomRadius: 14).path(in: .zero).isEmpty)
    }
}
