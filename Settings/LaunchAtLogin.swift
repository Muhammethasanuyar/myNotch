import Foundation
import Observation
import ServiceManagement

/// What the login item registration looks like to the user.
nonisolated enum LaunchAtLoginState: Equatable, Sendable {
    case enabled
    case disabled
    /// Registered, but the user has to allow it in System Settings → General → Login Items.
    case requiresApproval
    /// launchd does not know the bundle; typical for a build run from a scratch directory.
    case notFound

    init(status: SMAppService.Status) {
        switch status {
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notFound: self = .notFound
        case .notRegistered: self = .disabled
        @unknown default: self = .disabled
        }
    }

    /// Whether the toggle should read as on.
    var isOn: Bool {
        self == .enabled || self == .requiresApproval
    }
}

/// Registers the app itself as a login item through `SMAppService`; the system owns the truth, so
/// nothing is stored in defaults and `refresh()` re-reads it whenever the pane appears.
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var state: LaunchAtLoginState
    private(set) var lastError: String?

    init() {
        state = LaunchAtLoginState(status: SMAppService.mainApp.status)
    }

    func refresh() {
        state = LaunchAtLoginState(status: SMAppService.mainApp.status)
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    /// System Settings → General → Login Items, where a pending approval is granted.
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
