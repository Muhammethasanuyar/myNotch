// The line protocol of mediaremote-adapter (BSD-3-Clause, https://github.com/ungive/mediaremote-adapter),
// read from the outside: nothing here is adapted from its sources, only its documented output.

import Foundation

/// A JSON value as the adapter prints it; artwork arrives as a base64 string.
nonisolated enum AdapterValue: Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init?(json: Any) {
        if json is NSNull { self = .null; return }
        if let number = json as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { self = .bool(number.boolValue) } else { self = .number(number.doubleValue) }
            return
        }
        if let string = json as? String { self = .string(string); return }
        return nil
    }

    var string: String? { if case .string(let value) = self { return value }; return nil }
    var number: Double? { if case .number(let value) = self { return value }; return nil }
    var bool: Bool? { if case .bool(let value) = self { return value }; return nil }
}

nonisolated enum AdapterDecodeError: Error, Equatable {
    case notAnObject
    case unexpectedType(String)
}

/// One line of `stream`: `{type, diff, payload}`.
nonisolated struct AdapterEnvelope: Equatable, Sendable {
    let isDiff: Bool
    let payload: [String: AdapterValue]

    /// `nil` for the literal `null` line, which means "nothing is playing".
    static func decode(_ line: Data) throws -> AdapterEnvelope? {
        let text = String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text == "null" { return nil }
        guard let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { throw AdapterDecodeError.notAnObject }
        // `get` prints the payload itself; `stream` wraps it in an envelope.
        if let type = object["type"] as? String {
            guard type == "data" else { throw AdapterDecodeError.unexpectedType(type) }
            let raw = object["payload"] as? [String: Any] ?? [:]
            return AdapterEnvelope(isDiff: object["diff"] as? Bool ?? false, payload: values(raw))
        }
        return AdapterEnvelope(isDiff: false, payload: values(object))
    }

    private static func values(_ raw: [String: Any]) -> [String: AdapterValue] {
        raw.reduce(into: [:]) { result, pair in
            if let value = AdapterValue(json: pair.value) { result[pair.key] = value }
        }
    }
}

/// The live now-playing dictionary, merged from full and diff lines.
nonisolated struct AdapterPayload: Equatable, Sendable {
    private(set) var values: [String: AdapterValue] = [:]

    /// Keys that identify the item; a change in any of them is a track change.
    static let identityKeys = ["processIdentifier", "bundleIdentifier", "parentApplicationBundleIdentifier", "title", "artist", "album"]
    static let artworkKeys = ["artworkData", "artworkMimeType"]

    var isEmpty: Bool { values.isEmpty }

    /// Applies a line; returns whether the item changed. A full line without artwork for the same
    /// item keeps the artwork it already had — the adapter drops it while it is fetching anew.
    mutating func apply(_ envelope: AdapterEnvelope) -> Bool {
        let before = identity
        if envelope.isDiff {
            for (key, value) in envelope.payload {
                if value == .null { values.removeValue(forKey: key) } else { values[key] = value }
            }
        } else {
            var next = envelope.payload
            if Self.identity(of: next) == before, next["artworkData"] == nil {
                for key in Self.artworkKeys where values[key] != nil { next[key] = values[key] }
            }
            values = next
        }
        return identity != before
    }

    var identity: [AdapterValue?] { Self.identity(of: values) }

    private static func identity(of values: [String: AdapterValue]) -> [AdapterValue?] {
        identityKeys.map { values[$0] }
    }
}

/// What the adapter knows about the current item, typed.
nonisolated struct NowPlayingSnapshot: Equatable, Sendable {
    let processIdentifier: Int32
    let bundleIdentifier: String?
    let parentApplicationBundleIdentifier: String?
    let title: String
    let artist: String?
    let album: String?
    let isPlaying: Bool
    let duration: TimeInterval?
    let elapsedTime: TimeInterval?
    let timestamp: Date?
    let playbackRate: Double?
    let contentItemIdentifier: String?
    let artworkMimeType: String?
    let artworkBase64: String?

    /// Mandatory: the process, a title and the playing flag. `bundleIdentifier` is not guaranteed.
    init?(payload: AdapterPayload) {
        let values = payload.values
        guard let pid = values["processIdentifier"]?.number,
              let title = values["title"]?.string, !title.isEmpty,
              let playing = values["playing"]?.bool else { return nil }
        processIdentifier = Int32(pid)
        bundleIdentifier = values["bundleIdentifier"]?.string
        parentApplicationBundleIdentifier = values["parentApplicationBundleIdentifier"]?.string
        self.title = title
        artist = values["artist"]?.string
        album = values["album"]?.string
        isPlaying = playing
        duration = values["duration"]?.number
        elapsedTime = values["elapsedTime"]?.number
        timestamp = values["timestamp"]?.string.flatMap(Self.date(from:))
        playbackRate = values["playbackRate"]?.number
        contentItemIdentifier = values["contentItemIdentifier"]?.string
        artworkMimeType = values["artworkMimeType"]?.string
        artworkBase64 = values["artworkData"]?.string
    }

    /// The app to name and draw: the player itself, else the app hosting it (a browser tab's parent).
    var sourceBundleID: String? {
        bundleIdentifier ?? parentApplicationBundleIdentifier
    }

    var trackID: String {
        contentItemIdentifier ?? [sourceBundleID ?? String(processIdentifier), title, artist ?? "", album ?? ""].joined(separator: "|")
    }

    /// The controller's state: the playhead is anchored at the adapter's own timestamp, so the
    /// extrapolation the notch already does covers the time since.
    func mediaState(providerID: String, providerName: String, now: Date) -> MediaState {
        let anchor = timestamp ?? now
        return MediaState(
            providerID: providerID,
            providerName: providerName,
            trackID: trackID,
            title: title,
            artist: artist ?? "",
            album: album ?? "",
            isPlaying: isPlaying && (playbackRate ?? 1) > 0,
            duration: duration.flatMap { $0 > 0 ? $0 : nil },
            elapsed: elapsedTime ?? 0,
            elapsedAt: anchor,
            artwork: nil
        )
    }

    static func date(from text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

/// Pure decisions about the generic source.
nonisolated enum GenericSourceRules {
    /// Spotify and Music have their own providers; the generic one stays quiet for them.
    static func isOwnedByScriptProvider(_ snapshot: NowPlayingSnapshot, owned: Set<String>) -> Bool {
        [snapshot.bundleIdentifier, snapshot.parentApplicationBundleIdentifier].contains { $0.map(owned.contains) ?? false }
    }

    /// The name the switcher shows: the running app's, else a generic label.
    static func sourceName(_ snapshot: NowPlayingSnapshot, runningAppName: (Int32) -> String?, fallback: String) -> String {
        runningAppName(snapshot.processIdentifier) ?? fallback
    }
}

/// Seconds → the microseconds the adapter's `seek` takes.
nonisolated func adapterMicroseconds(_ seconds: TimeInterval) -> Int64 {
    Int64((max(0, seconds) * 1_000_000).rounded())
}
