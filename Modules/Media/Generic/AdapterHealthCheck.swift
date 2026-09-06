import CryptoKit
import Foundation
import os

/// Whether the bundled adapter can still reach MediaRemote on this macOS.
nonisolated enum AdapterHealth: Equatable, Sendable {
    case unchecked
    case ok
    /// The app was built without the artefacts.
    case artefactsMissing
    /// `test` could not launch its helper.
    case testClientFailed
    /// The helper never reported `setup_done`.
    case setupTimeout
    /// The helper published a fake item and the adapter still saw nothing: the private API is gone.
    case noData
    /// Any other non-zero exit, including the stream dying mid-way.
    case broken(exitCode: Int32)
    case timedOut

    init(exitCode: Int32) {
        switch exitCode {
        case 0: self = .ok
        case 2: self = .testClientFailed
        case 3: self = .setupTimeout
        case 4: self = .noData
        default: self = .broken(exitCode: exitCode)
        }
    }

    var storedValue: String {
        switch self {
        case .unchecked: "unchecked"
        case .ok: "ok"
        case .artefactsMissing: "artefactsMissing"
        case .testClientFailed: "testClientFailed"
        case .setupTimeout: "setupTimeout"
        case .noData: "noData"
        case .broken(let code): "broken:\(code)"
        case .timedOut: "timedOut"
        }
    }

    init?(storedValue: String) {
        switch storedValue {
        case "unchecked": self = .unchecked
        case "ok": self = .ok
        case "artefactsMissing": self = .artefactsMissing
        case "testClientFailed": self = .testClientFailed
        case "setupTimeout": self = .setupTimeout
        case "noData": self = .noData
        case "timedOut": self = .timedOut
        default:
            guard storedValue.hasPrefix("broken:"), let code = Int32(storedValue.dropFirst("broken:".count)) else { return nil }
            self = .broken(exitCode: code)
        }
    }
}

/// A `test` result, valid for one OS build and one set of bundled artefacts: the private API can
/// vanish with a macOS update and the adapter can change with a re-vendoring, and the check itself
/// briefly publishes a fake now-playing item other apps can see, so it is not something to run
/// casually — in particular not on every app version bump.
nonisolated struct AdapterHealthRecord: Equatable, Sendable {
    let status: AdapterHealth
    let osBuild: String
    /// Fingerprint of the bundled framework and test client (`AdapterHealthCheck.artefact(for:)`).
    let artefact: String
    let checkedAt: Date

    var storedValue: String {
        [status.storedValue, osBuild, artefact, String(checkedAt.timeIntervalSince1970)].joined(separator: "|")
    }

    init(status: AdapterHealth, osBuild: String, artefact: String, checkedAt: Date) {
        self.status = status
        self.osBuild = osBuild
        self.artefact = artefact
        self.checkedAt = checkedAt
    }

    init?(storedValue: String) {
        let parts = storedValue.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, let status = AdapterHealth(storedValue: parts[0]), let seconds = TimeInterval(parts[3]) else { return nil }
        self.init(status: status, osBuild: parts[1], artefact: parts[2], checkedAt: Date(timeIntervalSince1970: seconds))
    }

    func isCurrent(osBuild: String, artefact: String) -> Bool {
        self.osBuild == osBuild && self.artefact == artefact
    }
}

/// Runs and remembers the health check.
@MainActor
final class AdapterHealthCheck {
    static let key = "genericPlayerHealth"
    private let defaults: UserDefaults
    /// The artefacts this app carries; a re-vendored adapter gets a fresh verdict.
    let artefact: String
    private static let log = Logger(subsystem: "com.emre.mynotch", category: "mediaremote-adapter")

    init(defaults: UserDefaults = .standard, artefact: String) {
        self.defaults = defaults
        self.artefact = artefact
    }

    static var osBuild: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    /// SHA-256 over the framework binary and the test client, shortened: what actually runs, so a
    /// version bump alone never repeats the check. `"none"` when the artefacts are not bundled.
    nonisolated static func artefact(for paths: MediaRemoteAdapterProcess.Paths?) -> String {
        guard let paths else { return "none" }
        var hasher = SHA256()
        let binary = paths.framework.appendingPathComponent("Versions/A/MediaRemoteAdapter")
        for url in [binary, paths.testClient].compactMap({ $0 }) {
            if let data = try? Data(contentsOf: url) { hasher.update(data: data) }
        }
        return hasher.finalize().prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// The last result, if it was taken on this OS build with these artefacts.
    func cached() -> AdapterHealthRecord? {
        guard let stored = defaults.string(forKey: Self.key), let record = AdapterHealthRecord(storedValue: stored),
              record.isCurrent(osBuild: Self.osBuild, artefact: artefact) else { return nil }
        return record
    }

    func record(_ status: AdapterHealth) -> AdapterHealthRecord {
        let record = AdapterHealthRecord(status: status, osBuild: Self.osBuild, artefact: artefact, checkedAt: Date())
        defaults.set(record.storedValue, forKey: Self.key)
        return record
    }

    /// Runs `test` (ten seconds at most) and stores the verdict.
    func run(process: MediaRemoteAdapterProcess) async -> AdapterHealthRecord {
        do {
            let result = try await process.run(.test, timeout: 15)
            let status = AdapterHealth(exitCode: result.status)
            if status != .ok {
                Self.log.error("adapter test exited \(result.status, privacy: .public): \(String(decoding: result.stderr, as: UTF8.self).suffix(200), privacy: .public)")
            }
            return record(status)
        } catch is ProcessRunnerError {
            return record(.timedOut)
        } catch {
            return record(.broken(exitCode: -1))
        }
    }
}
