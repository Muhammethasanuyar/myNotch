import XCTest
@testable import MyNotch

final class MediaRemoteAdapterTests: XCTestCase {
    private let paths = MediaRemoteAdapterProcess.Paths(
        perl: URL(fileURLWithPath: "/usr/bin/perl"),
        script: URL(fileURLWithPath: "/App/Resources/mediaremote-adapter.pl"),
        framework: URL(fileURLWithPath: "/App/Frameworks/MediaRemoteAdapter.framework"),
        testClient: URL(fileURLWithPath: "/App/Resources/MediaRemoteAdapterTestClient")
    )

    func testArgumentsFollowTheAdaptersOrder() {
        XCTAssertEqual(MediaRemoteAdapterProcess.arguments(.get, paths: paths), ["/App/Resources/mediaremote-adapter.pl", "/App/Frameworks/MediaRemoteAdapter.framework", "get"])
        XCTAssertEqual(MediaRemoteAdapterProcess.arguments(.stream(debounceMS: 250, includeArtwork: true), paths: paths).suffix(2), ["stream", "--debounce=250"])
        XCTAssertEqual(MediaRemoteAdapterProcess.arguments(.stream(debounceMS: 100, includeArtwork: false), paths: paths).suffix(3), ["stream", "--debounce=100", "--no-artwork"])
        XCTAssertEqual(MediaRemoteAdapterProcess.arguments(.send(.togglePlayPause), paths: paths).suffix(2), ["send", "2"])
        XCTAssertEqual(MediaRemoteAdapterProcess.arguments(.seek(microseconds: 42_500_000), paths: paths).suffix(2), ["seek", "42500000"])
        XCTAssertEqual(MediaRemoteAdapterProcess.arguments(.test, paths: paths), ["/App/Resources/mediaremote-adapter.pl", "/App/Frameworks/MediaRemoteAdapter.framework", "/App/Resources/MediaRemoteAdapterTestClient", "test"], "only test gets the helper, before the function name")
        for command in [MediaRemoteAdapterProcess.Command.get, .stream(debounceMS: 250, includeArtwork: true), .send(.play), .seek(microseconds: 1), .test] {
            let arguments = MediaRemoteAdapterProcess.arguments(command, paths: paths)
            XCTAssertFalse(arguments.contains { $0.hasPrefix("--micros") || $0 == "--no-diff" || $0.hasPrefix("--human") }, "never the flags that cost more than they give")
        }
    }

    func testCommandsMapToMediaRemoteIDs() {
        XCTAssertEqual(MediaRemoteCommand(.playPause), .togglePlayPause)
        XCTAssertEqual(MediaRemoteCommand(.next), .nextTrack)
        XCTAssertEqual(MediaRemoteCommand(.previous)?.rawValue, 5)
        XCTAssertNil(MediaRemoteCommand(.seek(3)), "seek has its own command")
        XCTAssertNil(MediaRemoteCommand(.setFavorite(true, trackID: "x")))
        XCTAssertEqual(adapterMicroseconds(42.5), 42_500_000)
        XCTAssertEqual(adapterMicroseconds(-3), 0)
    }

    func testLineAccumulatorWaitsForNewlines() {
        var accumulator = LineAccumulator()
        XCTAssertEqual(accumulator.append(Data("{\"a\":1".utf8)), [])
        XCTAssertEqual(accumulator.append(Data("}\n{\"b\":2}\n\n{\"c\"".utf8)).map { String(decoding: $0, as: UTF8.self) }, ["{\"a\":1}", "{\"b\":2}"])
        XCTAssertEqual(accumulator.append(Data(":3}\n".utf8)).map { String(decoding: $0, as: UTF8.self) }, ["{\"c\":3}"])
        let big = String(repeating: "A", count: 400_000)
        XCTAssertEqual(accumulator.append(Data(("{\"artworkData\":\"" + big + "\"}\n").utf8)).count, 1, "a large artwork line arrives whole")
    }

    func testEnvelopeDecoding() throws {
        let envelope = try AdapterEnvelope.decode(Data(#"{"type":"data","diff":false,"payload":{"title":"Song","playing":true,"processIdentifier":42,"duration":300.5}}"#.utf8))
        XCTAssertEqual(envelope?.isDiff, false)
        XCTAssertEqual(envelope?.payload["title"], .string("Song"))
        XCTAssertEqual(envelope?.payload["playing"], .bool(true), "booleans stay booleans")
        XCTAssertEqual(envelope?.payload["processIdentifier"], .number(42))
        XCTAssertNil(try AdapterEnvelope.decode(Data("null\n".utf8)), "null means nothing is playing")
        XCTAssertEqual(try AdapterEnvelope.decode(Data(#"{"type":"data","diff":true,"payload":{}}"#.utf8))?.payload.isEmpty, true)
        let bare = try AdapterEnvelope.decode(Data(#"{"title":"From get","playing":false,"processIdentifier":1}"#.utf8))
        XCTAssertEqual(bare?.isDiff, false, "get prints the payload without an envelope")
        XCTAssertThrowsError(try AdapterEnvelope.decode(Data("{not json".utf8)))
        XCTAssertThrowsError(try AdapterEnvelope.decode(Data(#"{"type":"weird"}"#.utf8)))
    }

    func testPayloadMergesDiffsAndKeepsArtworkForTheSameItem() throws {
        var payload = AdapterPayload()
        let full = try AdapterEnvelope.decode(Data(#"{"type":"data","diff":false,"payload":{"processIdentifier":7,"title":"A","artist":"X","playing":true,"elapsedTime":1,"artworkData":"QUJD"}}"#.utf8))!
        XCTAssertTrue(payload.apply(full), "the first item is a change")
        let progress = try AdapterEnvelope.decode(Data(#"{"type":"data","diff":true,"payload":{"elapsedTime":31,"playing":false}}"#.utf8))!
        XCTAssertFalse(payload.apply(progress))
        XCTAssertEqual(payload.values["elapsedTime"], .number(31))
        XCTAssertEqual(payload.values["playing"], .bool(false))
        XCTAssertEqual(payload.values["artworkData"], .string("QUJD"), "untouched keys stay")
        let removal = try AdapterEnvelope.decode(Data(#"{"type":"data","diff":true,"payload":{"artist":null}}"#.utf8))!
        XCTAssertTrue(payload.apply(removal), "the artist is part of the identity")
        XCTAssertNil(payload.values["artist"])
        let refetch = try AdapterEnvelope.decode(Data(#"{"type":"data","diff":false,"payload":{"processIdentifier":7,"title":"A","playing":true}}"#.utf8))!
        XCTAssertFalse(payload.apply(refetch))
        XCTAssertEqual(payload.values["artworkData"], .string("QUJD"), "a full line without artwork keeps the artwork of the same item")
        let other = try AdapterEnvelope.decode(Data(#"{"type":"data","diff":false,"payload":{"processIdentifier":7,"title":"B","playing":true}}"#.utf8))!
        XCTAssertTrue(payload.apply(other))
        XCTAssertNil(payload.values["artworkData"], "a new item starts without the old artwork")
    }

    func testSnapshotNeedsTheMandatoryKeysAndFallsBackForTheBundle() throws {
        var payload = AdapterPayload()
        _ = payload.apply(try AdapterEnvelope.decode(Data(#"{"type":"data","diff":false,"payload":{"processIdentifier":91117,"title":"Talk","artist":"Someone","playing":false,"playbackRate":0,"elapsedTime":8.05,"duration":795.98,"timestamp":"2026-09-06T15:01:01Z","parentApplicationBundleIdentifier":"com.apple.Safari"}}"#.utf8))!)
        let snapshot = NowPlayingSnapshot(payload: payload)
        XCTAssertEqual(snapshot?.sourceBundleID, "com.apple.Safari", "no bundleIdentifier: the parent app names the source")
        XCTAssertEqual(snapshot?.timestamp, ISO8601DateFormatter().date(from: "2026-09-06T15:01:01Z"))
        let state = snapshot!.mediaState(providerID: "generic", providerName: "Safari", now: Date())
        XCTAssertEqual(state.title, "Talk")
        XCTAssertEqual(state.duration, 795.98)
        XCTAssertEqual(state.elapsed, 8.05)
        XCTAssertFalse(state.isPlaying)
        XCTAssertEqual(state.trackID, "com.apple.Safari|Talk|Someone|")
        XCTAssertNil(state.artwork, "artwork is written on request, not linked")

        var noTitle = AdapterPayload()
        _ = noTitle.apply(try AdapterEnvelope.decode(Data(#"{"type":"data","diff":false,"payload":{"processIdentifier":1,"title":"","playing":true}}"#.utf8))!)
        XCTAssertNil(NowPlayingSnapshot(payload: noTitle))
        var noPlaying = AdapterPayload()
        _ = noPlaying.apply(try AdapterEnvelope.decode(Data(#"{"type":"data","diff":false,"payload":{"processIdentifier":1,"title":"x"}}"#.utf8))!)
        XCTAssertNil(NowPlayingSnapshot(payload: noPlaying))

        var paused = AdapterPayload()
        _ = paused.apply(try AdapterEnvelope.decode(Data(#"{"type":"data","diff":false,"payload":{"processIdentifier":1,"title":"x","playing":true,"playbackRate":0,"contentItemIdentifier":"item-1"}}"#.utf8))!)
        let pausedState = NowPlayingSnapshot(payload: paused)!.mediaState(providerID: "generic", providerName: "App", now: Date())
        XCTAssertFalse(pausedState.isPlaying, "a zero rate is paused whatever the flag says")
        XCTAssertEqual(pausedState.trackID, "item-1", "the adapter's own item id wins when present")
    }

    func testScriptPlayersSilenceTheGenericSource() throws {
        let owners: Set<String> = ["com.spotify.client", "com.apple.Music"]
        func snapshot(_ bundle: String?, parent: String? = nil) -> NowPlayingSnapshot {
            var payload = AdapterPayload()
            var json = #"{"processIdentifier":1,"title":"x","playing":true"#
            if let bundle { json += #","bundleIdentifier":"\#(bundle)""# }
            if let parent { json += #","parentApplicationBundleIdentifier":"\#(parent)""# }
            _ = payload.apply(try! AdapterEnvelope.decode(Data((json + "}").utf8))!)
            return NowPlayingSnapshot(payload: payload)!
        }
        XCTAssertTrue(GenericSourceRules.isOwnedByScriptProvider(snapshot("com.spotify.client"), owned: owners))
        XCTAssertTrue(GenericSourceRules.isOwnedByScriptProvider(snapshot(nil, parent: "com.apple.Music"), owned: owners))
        XCTAssertFalse(GenericSourceRules.isOwnedByScriptProvider(snapshot("com.apple.Safari"), owned: owners))
        XCTAssertEqual(GenericSourceRules.sourceName(snapshot("com.apple.Safari"), runningAppName: { _ in "Safari" }, fallback: "Now Playing"), "Safari")
        XCTAssertEqual(GenericSourceRules.sourceName(snapshot(nil), runningAppName: { _ in nil }, fallback: "Now Playing"), "Now Playing")
    }

    func testHealthRecordsRoundTrip() {
        XCTAssertEqual(AdapterHealth(exitCode: 0), .ok)
        XCTAssertEqual(AdapterHealth(exitCode: 2), .testClientFailed)
        XCTAssertEqual(AdapterHealth(exitCode: 3), .setupTimeout)
        XCTAssertEqual(AdapterHealth(exitCode: 4), .noData)
        XCTAssertEqual(AdapterHealth(exitCode: 1), .broken(exitCode: 1))
        let record = AdapterHealthRecord(status: .broken(exitCode: 7), osBuild: "26.6.2", artefact: "a1b2c3d4e5f60718", checkedAt: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(AdapterHealthRecord(storedValue: record.storedValue), record)
        XCTAssertTrue(record.isCurrent(osBuild: "26.6.2", artefact: "a1b2c3d4e5f60718"))
        XCTAssertFalse(record.isCurrent(osBuild: "26.7", artefact: "a1b2c3d4e5f60718"), "a new macOS invalidates the verdict")
        XCTAssertFalse(record.isCurrent(osBuild: "26.6.2", artefact: "ffffffffffffffff"), "a re-vendored adapter invalidates it too")
        XCTAssertEqual(AdapterHealthCheck.artefact(for: nil), "none")
        XCTAssertEqual(AdapterHealthCheck.artefact(for: paths).count, 16, "missing files still hash to a stable short digest")
        XCTAssertNil(AdapterHealthRecord(storedValue: "garbage"))
        XCTAssertNil(AdapterHealth(storedValue: "broken:x"))
    }
}
