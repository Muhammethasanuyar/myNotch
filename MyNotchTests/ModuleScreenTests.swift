import XCTest
@testable import MyNotch

final class ModuleScreenTests: XCTestCase {
    private func screen(_ id: String, available: Bool = true) -> ModuleScreen {
        ModuleScreen(id: id, title: id.capitalized, symbolName: "circle", isAvailable: available)
    }

    func testOnlyAvailableScreensAreOffered() {
        let screens = [screen("claude"), screen("media", available: false), screen("demo")]
        XCTAssertEqual(ModuleScreenList.visible(screens, activeID: "claude").map(\.id), ["claude", "demo"])
    }

    func testTheScreenOnShowKeepsItsTabEvenWhenItGoesQuiet() {
        let screens = [screen("claude"), screen("media", available: false)]
        XCTAssertEqual(
            ModuleScreenList.visible(screens, activeID: "media").map(\.id),
            ["claude", "media"],
            "the card must not lose its own tab while the user is reading it"
        )
    }

    func testRegistrationOrderIsKept() {
        let screens = [screen("claude"), screen("media"), screen("demo")]
        XCTAssertEqual(ModuleScreenList.visible(screens, activeID: "demo").map(\.id), ["claude", "media", "demo"],
                       "icons must not jump around as availability changes")
    }

    func testASingleScreenNeedsNoSwitcher() {
        XCTAssertFalse(ModuleScreenList.shouldShow([]))
        XCTAssertFalse(ModuleScreenList.shouldShow([screen("claude")]))
        XCTAssertTrue(ModuleScreenList.shouldShow([screen("claude"), screen("media")]))
    }
}
