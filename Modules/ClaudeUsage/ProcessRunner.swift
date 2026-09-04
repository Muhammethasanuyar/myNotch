import Foundation

/// Result of a finished child process.
nonisolated struct ProcessResult: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: Data
}

nonisolated enum ProcessRunnerError: Error, Equatable {
    case launchFailed(String)
    case timedOut(TimeInterval)
}

/// Runs a command line tool on a private serial queue and hands back its output.
///
/// Both credential lookups (`/usr/bin/security`) and cost reports (`ccusage`) go through here, so
/// no `Process` ever blocks the main thread. Output is read before waiting for exit — the other way
/// round deadlocks once the child fills the 64 KB pipe buffer.
nonisolated enum ProcessRunner {
    private static let queue = DispatchQueue(label: "com.emre.mynotch.process", qos: .utility)

    static func run(_ executable: URL, arguments: [String], environment: [String: String]? = nil, timeout: TimeInterval = 30) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try execute(executable, arguments: arguments, environment: environment, timeout: timeout) })
            }
        }
    }

    private static func execute(_ executable: URL, arguments: [String], environment: [String: String]?, timeout: TimeInterval) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }

        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)

        let output = (try? stdout.fileHandleForReading.readToEnd()) ?? Data()
        let errors = (try? stderr.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        let timedOut = watchdog.isCancelled == false && process.terminationReason == .uncaughtSignal
        watchdog.cancel()
        if timedOut { throw ProcessRunnerError.timedOut(timeout) }
        return ProcessResult(status: process.terminationStatus, stdout: output, stderr: errors)
    }
}
