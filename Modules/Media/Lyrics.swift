import Foundation

/// One timed line of an LRC file. An empty `text` is meaningful: it blanks the display during
/// intros and instrumental breaks.
nonisolated struct LyricsLine: Equatable, Sendable {
    let time: TimeInterval
    let text: String
}

/// Timed lyrics for one track.
nonisolated struct Lyrics: Equatable, Sendable {
    let trackKey: String
    let lines: [LyricsLine]

    var isEmpty: Bool { lines.isEmpty }
}

/// What the lyrics view should render right now.
nonisolated enum LyricsStatus: Equatable, Sendable {
    case idle
    case loading
    case loaded(Lyrics)
    /// Looked up and there is nothing to show (no match, or an instrumental track).
    case unavailable
}

/// Parses the LRC format and answers "which line is playing now". Pure so the timing rules can be
/// tested without the network.
nonisolated enum LyricsParser {
    /// Parses an LRC document.
    ///
    /// Handles `[mm:ss]`, `[mm:ss.xx]` and `[mm:ss.xxx]`, several timestamps sharing one line, the
    /// `[offset:±ms]` tag, and ignores metadata tags such as `[ar:]` / `[ti:]` / `[al:]`.
    static func parse(_ lrc: String) -> [LyricsLine] {
        var lines: [LyricsLine] = []
        var offset: TimeInterval = 0

        for raw in lrc.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("[") else { continue }

            if let tagOffset = self.offset(in: line) {
                offset = tagOffset
                continue
            }

            let (stamps, text) = timestamps(in: line)
            guard !stamps.isEmpty else { continue }
            for stamp in stamps {
                lines.append(LyricsLine(time: max(0, stamp + offset), text: text))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }

    /// The line playing at `time`, or `nil` before the first timestamp.
    static func index(at time: TimeInterval, in lines: [LyricsLine]) -> Int? {
        guard let first = lines.first, time >= first.time else { return nil }
        var low = 0
        var high = lines.count - 1
        var result = 0
        while low <= high {
            let middle = (low + high) / 2
            if lines[middle].time <= time {
                result = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return result
    }

    // MARK: Private

    /// `[offset:+250]` shifts every timestamp, in milliseconds.
    private static func offset(in line: String) -> TimeInterval? {
        guard line.hasPrefix("[offset:"), let end = line.firstIndex(of: "]") else { return nil }
        let value = line[line.index(line.startIndex, offsetBy: 8)..<end]
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "+", with: "")
        return Double(value).map { $0 / 1000 }
    }

    /// Pulls every `[mm:ss.xx]` prefix off a line and returns them with the remaining text.
    private static func timestamps(in line: String) -> ([TimeInterval], String) {
        var stamps: [TimeInterval] = []
        var rest = Substring(line)

        while rest.hasPrefix("["), let end = rest.firstIndex(of: "]") {
            let body = rest[rest.index(after: rest.startIndex)..<end]
            guard let seconds = self.seconds(from: String(body)) else { break }
            stamps.append(seconds)
            rest = rest[rest.index(after: end)...]
        }
        return (stamps, String(rest).trimmingCharacters(in: .whitespaces))
    }

    /// `mm:ss`, `mm:ss.xx` or `mm:ss.xxx` → seconds. `nil` for metadata tags.
    private static func seconds(from body: String) -> TimeInterval? {
        let parts = body.split(separator: ":")
        guard parts.count == 2,
              let minutes = Double(parts[0]),
              let seconds = Double(parts[1].replacingOccurrences(of: ",", with: ".")) else { return nil }
        return minutes * 60 + seconds
    }
}
