import XCTest
@testable import MyNotch

/// A player MyNotch can read, without an app behind it.
@MainActor
private final class StubPlayer: MediaProvider {
    let id: String
    let displayName: String
    let bundleIdentifier: String
    let changeNotification: Notification.Name
    let symbolName = "music.note"
    let capabilities = MediaCapabilities(canShuffle: false, canRepeat: false, canFavorite: false, hasRepeatModes: false)

    var running = true
    var loaded: MediaState?
    private(set) var sent: [MediaCommand] = []

    init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifier = "com.example.\(id)"
        self.changeNotification = Notification.Name("com.example.\(id).changed")
    }

    func isRunning() -> Bool { running }
    func fetch() async throws -> MediaState? { loaded }
    func send(_ command: MediaCommand) async throws { sent.append(command) }
}

@MainActor
final class MediaScreensTests: XCTestCase {
    private let spotify = StubPlayer(id: "spotify", displayName: "Spotify")
    private let music = StubPlayer(id: "music", displayName: "Music")

    private func makeModule() -> MediaModule {
        MediaModule(controller: MediaController(providers: [spotify, music]))
    }

    private func playing(_ player: StubPlayer, _ title: String) -> MediaState {
        MediaState(
            providerID: player.id,
            providerName: player.displayName,
            trackID: "\(player.id):\(title)",
            title: title,
            artist: "Artist",
            album: "Album",
            isPlaying: true,
            duration: 200,
            elapsed: 10,
            elapsedAt: Date(),
            artwork: nil
        )
    }

    /// The controller's refresh runs in its own task; the stubs answer at once.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(120))
    }

    func testEveryRunningPlayerGetsItsOwnScreen() async throws {
        let module = makeModule()
        spotify.loaded = playing(spotify, "Derine İndik")
        module.controller.refresh()
        try await settle()

        XCTAssertEqual(module.screens.map(\.id), ["media.spotify", "media.music"])
        XCTAssertEqual(module.screens.map(\.title), ["Spotify", "Music"], "each pill is named after its app")
        XCTAssertEqual(module.screens.map(\.appBundleIdentifier), ["com.example.spotify", "com.example.music"])
        XCTAssertTrue(module.screens.allSatisfy { $0.moduleID == module.id })
        XCTAssertEqual(module.activeScreenID, "media.spotify", "the player with a track showing is the active screen")
    }

    func testAPlayerThatIsNotRunningHasNoScreen() async throws {
        let module = makeModule()
        music.running = false
        spotify.loaded = playing(spotify, "Track")
        module.controller.refresh()
        try await settle()

        XCTAssertEqual(module.screens.map(\.id), ["media.spotify"])
    }

    func testAJustOpenedPlayerAppearsBeforeItPlaysAnything() async throws {
        let module = makeModule()
        music.running = false
        spotify.loaded = playing(spotify, "Track")
        module.controller.refresh()
        try await settle()
        XCTAssertEqual(module.screens.count, 1)

        // Music was launched: nothing is loaded in it yet, but it belongs in the switcher.
        music.running = true
        module.controller.refresh()
        try await settle()

        XCTAssertEqual(module.screens.map(\.id), ["media.spotify", "media.music"])
        XCTAssertEqual(module.activeScreenID, "media.spotify", "and it does not steal the card")
    }

    func testChoosingAPlayerWithNothingLoadedStillTakesTheCard() async throws {
        let module = makeModule()
        spotify.loaded = playing(spotify, "Track")
        module.controller.refresh()
        try await settle()

        module.selectScreen("media.music")
        try await settle()

        XCTAssertEqual(module.activeScreenID, "media.music")
        XCTAssertNil(module.controller.state, "Music has nothing loaded, and Spotify must not take the card back")
        XCTAssertEqual(module.screens.count, 2, "both pills stay while both apps run")

        module.selectScreen("media.spotify")
        try await settle()
        XCTAssertEqual(module.controller.state?.title, "Track")
    }

    func testQuittingTheChosenPlayerReleasesTheCard() async throws {
        let module = makeModule()
        spotify.loaded = playing(spotify, "Track")
        module.controller.refresh()
        try await settle()
        module.selectScreen("media.music")
        try await settle()
        XCTAssertNil(module.controller.state)

        music.running = false
        module.controller.refresh()
        try await settle()

        XCTAssertEqual(module.screens.map(\.id), ["media.spotify"])
        XCTAssertEqual(module.controller.state?.title, "Track", "with the chosen player gone, the one that plays wins again")
        XCTAssertEqual(module.activeScreenID, "media.spotify")
    }

    func testAnUnknownScreenIsIgnored() async throws {
        let module = makeModule()
        spotify.loaded = playing(spotify, "Track")
        module.controller.refresh()
        try await settle()

        module.selectScreen("media.")
        module.selectScreen("claude")
        try await settle()

        XCTAssertEqual(module.activeScreenID, "media.spotify")
    }

    func testSeekingMovesThePlayheadAtOnceAndTellsThePlayer() async throws {
        let module = makeModule()
        spotify.loaded = playing(spotify, "Track")
        module.controller.refresh()
        try await settle()
        XCTAssertEqual(module.controller.state?.elapsed, 10)

        module.controller.seek(to: 150)
        XCTAssertEqual(module.controller.state?.elapsed, 150, "the bar must not snap back while the player catches up")
        try await settle()
        XCTAssertEqual(spotify.sent, [.seek(150)])

        module.controller.seek(to: 999)
        XCTAssertEqual(module.controller.state?.elapsed, 200, "clamped to the track")
        module.controller.seek(to: -5)
        XCTAssertEqual(module.controller.state?.elapsed, 0)
    }
}
