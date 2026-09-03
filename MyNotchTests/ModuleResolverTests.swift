import XCTest
@testable import MyNotch

final class ModuleResolverTests: XCTestCase {
    func testNoModulesMeansNobodyOwnsTheNotch() {
        XCTAssertNil(ModuleResolver.resolve([]))
    }

    func testAllIdleMeansNobodyOwnsTheNotch() {
        let snapshots = [
            ModuleSnapshot(id: "media", priority: 10, activity: .idle),
            ModuleSnapshot(id: "claude", priority: 5, activity: .idle)
        ]
        XCTAssertNil(ModuleResolver.resolve(snapshots))
    }

    func testLiveBeatsIdleRegardlessOfPriority() {
        let snapshots = [
            ModuleSnapshot(id: "media", priority: 100, activity: .idle),
            ModuleSnapshot(id: "claude", priority: 1, activity: .live)
        ]
        XCTAssertEqual(ModuleResolver.resolve(snapshots)?.id, "claude")
    }

    func testUrgentBeatsHigherPriorityLive() {
        let snapshots = [
            ModuleSnapshot(id: "media", priority: 100, activity: .live),
            ModuleSnapshot(id: "claude", priority: 1, activity: .urgent)
        ]
        XCTAssertEqual(ModuleResolver.resolve(snapshots)?.id, "claude")
    }

    func testPriorityBreaksTiesWithinTheSameActivity() {
        let snapshots = [
            ModuleSnapshot(id: "media", priority: 10, activity: .live),
            ModuleSnapshot(id: "claude", priority: 20, activity: .live)
        ]
        XCTAssertEqual(ModuleResolver.resolve(snapshots)?.id, "claude")
    }

    func testEqualActivityAndPriorityResolvesDeterministically() {
        let a = ModuleSnapshot(id: "aaa", priority: 5, activity: .live)
        let b = ModuleSnapshot(id: "zzz", priority: 5, activity: .live)
        XCTAssertEqual(ModuleResolver.resolve([a, b])?.id, "aaa")
        XCTAssertEqual(ModuleResolver.resolve([b, a])?.id, "aaa", "order of registration must not matter")
    }

    func testDisabledModulesNeverWin() {
        let snapshots = [
            ModuleSnapshot(id: "media", priority: 100, activity: .urgent, isEnabled: false),
            ModuleSnapshot(id: "claude", priority: 1, activity: .live)
        ]
        XCTAssertEqual(ModuleResolver.resolve(snapshots)?.id, "claude")
    }

    func testPopupsAreAcceptedOnlyFromKnownEnabledModules() {
        let snapshots = [
            ModuleSnapshot(id: "media", priority: 10, activity: .idle),
            ModuleSnapshot(id: "claude", priority: 5, activity: .live, isEnabled: false)
        ]
        // Idle is fine: an idle module may still have something urgent to announce.
        XCTAssertTrue(ModuleResolver.acceptsPopup(from: "media", snapshots: snapshots))
        XCTAssertFalse(ModuleResolver.acceptsPopup(from: "claude", snapshots: snapshots))
        XCTAssertFalse(ModuleResolver.acceptsPopup(from: "unknown", snapshots: snapshots))
    }
}
