import ServiceManagement
import XCTest
@testable import MyNotch

final class LaunchAtLoginTests: XCTestCase {
    func testStatusMapsToWhatTheToggleShows() {
        XCTAssertEqual(LaunchAtLoginState(status: .enabled), .enabled)
        XCTAssertEqual(LaunchAtLoginState(status: .notRegistered), .disabled)
        XCTAssertEqual(LaunchAtLoginState(status: .requiresApproval), .requiresApproval)
        XCTAssertEqual(LaunchAtLoginState(status: .notFound), .notFound)
    }

    func testAPendingApprovalStillReadsAsOn() {
        XCTAssertTrue(LaunchAtLoginState.enabled.isOn)
        XCTAssertTrue(LaunchAtLoginState.requiresApproval.isOn)
        XCTAssertFalse(LaunchAtLoginState.disabled.isOn)
        XCTAssertFalse(LaunchAtLoginState.notFound.isOn)
    }
}
