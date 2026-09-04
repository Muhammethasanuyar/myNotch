import Foundation

// Adapted from https://github.com/ccusage/ccusage (MIT): the `CLAUDE_CONFIG_DIR` comma list and the
// two default roots, so the watcher looks where the cost tool looks.

/// Where Claude Code keeps its session logs.
nonisolated enum ClaudePaths {
    /// The `projects/` directories to watch: every entry of `CLAUDE_CONFIG_DIR` (comma-separated,
    /// each either a config dir or its `projects/` child), or both defaults that exist.
    static func projectsDirectories(environment: [String: String] = ProcessInfo.processInfo.environment,
                                    home: String = NSHomeDirectory(),
                                    exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [URL] {
        if let raw = environment[ClaudeCredentials.configDirectoryKey] {
            let roots = raw.split(separator: ",")
                .map { expandTilde($0.trimmingCharacters(in: .whitespaces), home: home) }
                .filter { !$0.isEmpty }
                .map { path -> String in
                    path.hasSuffix("/projects") ? path : path + "/projects"
                }
            return roots.filter(exists).map { URL(fileURLWithPath: $0, isDirectory: true) }
        }
        let xdg = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.config"
        return [xdg + "/claude/projects", home + "/.claude/projects"]
            .filter(exists)
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// `~` and `~/…` against `home`, so callers can inject a home for tests.
    static func expandTilde(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst(1) }
        return path
    }
}

/// What the last few lines of a session log say about it.
nonisolated struct SessionTail: Equatable, Sendable {
    var cwd: String?
    var sessionID: String?
    var lastTimestamp: Date?
    var lastModel: String?
    /// The user-set title, when the log carries a `custom-title` entry.
    var customTitle: String?

    /// Last path component of the working directory: the project as the user thinks of it.
    var projectName: String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }
}

/// The last bytes of a log file and whether they start at its very beginning.
nonisolated struct TailBytes: Equatable, Sendable {
    let data: Data
    /// True when the file was short enough to read whole, so the first line is not cut.
    let fromStart: Bool
}

nonisolated enum SessionTailParser {
    static let defaultTailBytes = 64 * 1024

    /// Reads at most `bytes` from the end of the file, so a 100 MB log costs one small read.
    static func readTail(of url: URL, bytes: Int = defaultTailBytes) -> TailBytes? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let start = end > UInt64(bytes) ? end - UInt64(bytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return nil }
        return TailBytes(data: data, fromStart: start == 0)
    }

    static func parse(_ tail: TailBytes) -> SessionTail {
        parse(tail.data, fromStart: tail.fromStart)
    }

    /// Walks the complete lines of a tail (the first may be cut, the last may still be written)
    /// and keeps the newest value of each field.
    static func parse(_ data: Data, fromStart: Bool) -> SessionTail {
        var tail = SessionTail()
        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        if !data.isEmpty, data.last != 0x0A { lines = Array(lines.dropLast()) }   // still being written
        if !fromStart, !lines.isEmpty { lines.removeFirst() }                      // cut at an arbitrary byte
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for line in lines {
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let cwd = object["cwd"] as? String, !cwd.isEmpty { tail.cwd = cwd }
            if let session = object["sessionId"] as? String, !session.isEmpty { tail.sessionID = session }
            if let stamp = object["timestamp"] as? String,
               let date = fractional.date(from: stamp) ?? ISO8601DateFormatter().date(from: stamp) {
                tail.lastTimestamp = date
            }
            if let message = object["message"] as? [String: Any], let model = message["model"] as? String, !model.hasPrefix("<") {
                tail.lastModel = model
            }
            if object["type"] as? String == "custom-title", let title = object["customTitle"] as? String {
                tail.customTitle = title
            }
        }
        return tail
    }
}
