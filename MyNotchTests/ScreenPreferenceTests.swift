import XCTest
@testable import MyNotch

final class ScreenPreferenceTests: XCTestCase {
    private let builtIn = ScreenPreference.Candidate(name: "Built-in Retina Display", hasNotch: true, isMain: true)
    private let external = ScreenPreference.Candidate(name: "Studio Display", hasNotch: false, isMain: false)

    func testAutomaticPrefersTheNotchScreen() {
        XCTAssertEqual(ScreenPreference.automatic.resolve(in: [external, builtIn]), builtIn)
    }

    func testAutomaticFallsBackToTheMainScreenThenTheFirst() {
        let mainExternal = ScreenPreference.Candidate(name: "LG", hasNotch: false, isMain: true)
        XCTAssertEqual(ScreenPreference.automatic.resolve(in: [external, mainExternal]), mainExternal)
        XCTAssertEqual(ScreenPreference.automatic.resolve(in: [external]), external)
        XCTAssertNil(ScreenPreference.automatic.resolve(in: []))
    }

    func testANamedScreenWinsWhileItIsConnected() {
        let preference = ScreenPreference.named("Studio Display")
        XCTAssertEqual(preference.resolve(in: [builtIn, external]), external)
        XCTAssertEqual(preference.resolve(in: [builtIn]), builtIn, "unplugged: back to automatic")
    }

    func testStoredValueRoundTrips() {
        XCTAssertEqual(ScreenPreference(storedValue: nil), .automatic)
        XCTAssertEqual(ScreenPreference(storedValue: ""), .automatic)
        XCTAssertEqual(ScreenPreference(storedValue: "automatic"), .automatic)
        XCTAssertEqual(ScreenPreference(storedValue: "LG"), .named("LG"))
        XCTAssertEqual(ScreenPreference.named("LG").storedValue, "LG")
        XCTAssertEqual(ScreenPreference.automatic.storedValue, "automatic")
    }
}
