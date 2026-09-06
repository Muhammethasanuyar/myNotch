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

/// A `test` result, valid for one OS build and one app version: the private API can vanish with
/// either, and the check itself briefly publishes a fake now-playing item other apps can see, so
/// it is not something to run casually.
nonisolated struct AdapterHealthRecord: Equatable, Sendable {
    let status: AdapterHealth
    let osBuild: String
    let appVersion: String
    let checkedAt: Date

    var storedValue: String {
        [status.storedValue, osBuild, appVersion, String(checkedAt.timeIntervalSince1970)].joined(separator: "|")
    }

    init(status: AdapterHealth, osBuild: String, appVersion: String, checkedAt: Date) {
        self.status = status
        self.osBuild = osBuild
        self.appVersion = appVersion
        self.checkedAt = checkedAt
    }

    init?(storedValue: String) {
        let parts = storedValue.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, let status = AdapterHealth(storedValue: parts[0]), let seconds = TimeInterval(parts[3]) else { return nil }
        self.init(status: status, osBuild: parts[1], appVersion: parts[2], checkedAt: Date(timeIntervalSince1970: seconds))
    }

    func isCurrent(osBuild: String, appVersion: String) -> Bool {
        self.osBuild == osBuild && self.appVersion == appVersion
    }
}

/// Runs and remembers the health check.
@MainActor
final class AdapterHealthCheck {
    static let key = "genericPlayerHealth"
    private let defaults: UserDefaults
    private static let log = Logger(subsystem: "com.emre.mynotch", category: "mediaremote-adapter")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static var osBuild: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0") + "/" + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0")
    }

    /// The last result, if it was taken on this OS build with this app version.
    func cached() -> AdapterHealthRecord? {
        guard let stored = defaults.string(forKey: Self.key), let record = AdapterHealthRecord(storedValue: stored),
              record.isCurrent(osBuild: Self.osBuild, appVersion: Self.appVersion) else { return nil }
        return record
    }

    func record(_ status: AdapterHealth) -> AdapterHealthRecord {
        let record = AdapterHealthRecord(status: status, osBuild: Self.osBuild, appVersion: Self.appVersion, checkedAt: Date())
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
