import Foundation

/// Runs AppleScript. Injected into providers so tests can stub the output instead of talking to
/// real apps.
protocol AppleScriptRunning: Sendable {
    /// - Returns: the script's stdout, trimmed.
    func run(_ source: String) async throws -> String
}

/// What can go wrong while talking to a media app.
nonisolated enum AppleScriptError: Error, Equatable {
    /// macOS has not granted Automation for this app pair (Apple event error -1743).
    case permissionDenied
    /// The target app is not running or refused the event (-600 and friends).
    case appUnavailable
    case failed(status: Int32, message: String)
}

/// Executes scripts through `/usr/bin/osascript` on a private serial queue.
///
/// `NSAppleScript` would avoid the process spawn (and its XProtect scan) but is documented as
/// main-thread-only, and this project forbids AppleScript on the main thread. Calls are rare —
/// notification-driven plus a slow recovery poll — so a ~50 ms process round-trip is the cheaper
/// trade. If the frequency ever rises, the replacement is a compiled-script cache on a dedicated
/// thread with a run loop.
final class AppleScriptRunner: AppleScriptRunning {
    private let queue = DispatchQueue(label: "com.emre.mynotch.applescript", qos: .userInitiated)

    func run(_ source: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try Self.execute(source) })
            }
        }
    }

    private nonisolated static func execute(_ source: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
        } catch {
            throw AppleScriptError.failed(status: -1, message: error.localizedDescription)
        }

        let outputData = (try? output.fileHandleForReading.readToEnd()) ?? Data()
        let errorData = (try? error.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorData, as: UTF8.self)
            throw Self.mapError(status: process.terminationStatus, message: message)
        }
        return String(decoding: outputData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Turns osascript's stderr into something the module can act on.
    nonisolated static func mapError(status: Int32, message: String) -> AppleScriptError {
        if message.contains("-1743") || message.localizedCaseInsensitiveContains("not allowed") {
            return .permissionDenied
        }
        if message.contains("-600") || message.contains("-609") || message.contains("-1728") {
            return .appUnavailable
        }
        return .failed(status: status, message: message.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
