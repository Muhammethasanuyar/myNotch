// Runs mediaremote-adapter (BSD-3-Clause, https://github.com/ungive/mediaremote-adapter) as a child
// process. The framework is loaded by /usr/bin/perl, never by this app: that process boundary is
// what lets it read the private MediaRemote framework on macOS 15.4 and later.
//
// Privacy: everything stays on this Mac. The child reads what the system reports as playing and
// prints it to a pipe; nothing is sent anywhere.

import Foundation
import os

/// The MediaRemote command ids the adapter's `send` accepts.
nonisolated enum MediaRemoteCommand: Int, Equatable, Sendable {
    case play = 0, pause, togglePlayPause, stop, nextTrack, previousTrack, toggleShuffle, toggleRepeat
    case beginFastForward, endFastForward, beginRewind, endRewind, skipBackward15, skipForward15

    init?(_ command: MediaCommand) {
        switch command {
        case .playPause: self = .togglePlayPause
        case .next: self = .nextTrack
        case .previous: self = .previousTrack
        case .toggleShuffle: self = .toggleShuffle
        case .cycleRepeat: self = .toggleRepeat
        case .seek, .setFavorite: return nil
        }
    }
}

/// What the `stream` child prints: a payload line, a stderr line, or its exit.
nonisolated enum AdapterLine: Equatable, Sendable {
    case payload(Data)
    case diagnostic(String)
    case exited(Int32)
}

/// Splits pipe chunks into complete lines; a partial line waits for the next chunk.
nonisolated struct LineAccumulator: Sendable {
    private var buffer = Data()

    mutating func append(_ chunk: Data) -> [Data] {
        buffer.append(chunk)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            if !line.isEmpty { lines.append(Data(line)) }
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        return lines
    }
}

nonisolated final class MediaRemoteAdapterProcess: @unchecked Sendable {
    /// Where the bundled artefacts are; `nil` when the app was built without them.
    struct Paths: Equatable, Sendable {
        let perl: URL
        let script: URL
        let framework: URL
        let testClient: URL?

        static func bundled(_ bundle: Bundle = .main) -> Paths? {
            guard let script = bundle.url(forResource: "mediaremote-adapter", withExtension: "pl"),
                  let frameworks = bundle.privateFrameworksURL else { return nil }
            let framework = frameworks.appendingPathComponent("MediaRemoteAdapter.framework")
            guard FileManager.default.fileExists(atPath: framework.path) else { return nil }
            return Paths(
                perl: URL(fileURLWithPath: "/usr/bin/perl"),
                script: script,
                framework: framework,
                testClient: bundle.url(forResource: "MediaRemoteAdapterTestClient", withExtension: nil)
            )
        }
    }

    enum Command: Equatable, Sendable {
        case get
        case stream(debounceMS: Int, includeArtwork: Bool)
        case send(MediaRemoteCommand)
        case seek(microseconds: Int64)
        case test
    }

    /// `FRAMEWORK [TEST_CLIENT] FUNCTION [OPTIONS]`, in that order; only `test` gets the client.
    /// Units stay the adapter's defaults (seconds, ISO-8601) and diffs stay on — `--micros`,
    /// `--no-diff` and `--human-readable` would each cost more than they give.
    static func arguments(_ command: Command, paths: Paths) -> [String] {
        var arguments = [paths.script.path, paths.framework.path]
        switch command {
        case .get:
            arguments.append("get")
        case .stream(let debounceMS, let includeArtwork):
            arguments += ["stream", "--debounce=\(debounceMS)"]
            if !includeArtwork { arguments.append("--no-artwork") }
        case .send(let command):
            arguments += ["send", String(command.rawValue)]
        case .seek(let microseconds):
            arguments += ["seek", String(microseconds)]
        case .test:
            if let client = paths.testClient { arguments.append(client.path) }
            arguments.append("test")
        }
        return arguments
    }

    let paths: Paths
    private var streamProcess: Process?
    private var lock = os_unfair_lock()
    private static let log = Logger(subsystem: "com.emre.mynotch", category: "mediaremote-adapter")

    init(paths: Paths) {
        self.paths = paths
    }

    /// A short-lived command: `get`, `send`, `seek`, `test`.
    func run(_ command: Command, timeout: TimeInterval = 10) async throws -> ProcessResult {
        try await ProcessRunner.run(paths.perl, arguments: Self.arguments(command, paths: paths), environment: nil, timeout: timeout)
    }

    /// The long-lived `stream`: one line per update until the child exits or the stream is dropped.
    func lines(debounceMS: Int, includeArtwork: Bool) -> AsyncStream<AdapterLine> {
        AsyncStream { continuation in
            let process = Process()
            process.executableURL = paths.perl
            process.arguments = Self.arguments(.stream(debounceMS: debounceMS, includeArtwork: includeArtwork), paths: paths)
            process.standardInput = FileHandle.nullDevice
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            let output = LineBuffer()
            let errors = LineBuffer()
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                for line in output.append(chunk) { continuation.yield(.payload(line)) }
            }
            stderr.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                for line in errors.append(chunk) { continuation.yield(.diagnostic(String(decoding: line, as: UTF8.self))) }
            }
            process.terminationHandler = { process in
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                for line in output.append(stdout.fileHandleForReading.availableData) { continuation.yield(.payload(line)) }
                continuation.yield(.exited(process.terminationStatus))
                continuation.finish()
            }
            continuation.onTermination = { [weak self] _ in self?.terminate() }
            do {
                try process.run()
                os_unfair_lock_lock(&lock)
                streamProcess = process
                os_unfair_lock_unlock(&lock)
            } catch {
                Self.log.error("could not launch the adapter: \(String(describing: error), privacy: .public)")
                continuation.yield(.exited(-1))
                continuation.finish()
            }
        }
    }

    /// SIGTERM and wait: the child unregisters its notifications on the way out.
    func terminate() {
        os_unfair_lock_lock(&lock)
        let process = streamProcess
        streamProcess = nil
        os_unfair_lock_unlock(&lock)
        guard let process, process.isRunning else { return }
        process.terminate()
        process.waitUntilExit()
    }

    /// A crash of the app can leave the perl child behind; nothing else runs our script.
    static func killOrphans(scriptPath: String) async {
        _ = try? await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/pkill"), arguments: ["-f", scriptPath], environment: nil, timeout: 5)
    }
}

/// A line accumulator safe to feed from a pipe's background thread.
nonisolated private final class LineBuffer: @unchecked Sendable {
    private var accumulator = LineAccumulator()
    private var lock = os_unfair_lock()

    func append(_ chunk: Data) -> [Data] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return accumulator.append(chunk)
    }
}
