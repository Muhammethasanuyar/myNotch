// Adapted from Lakr233/NotchDrop (MIT): Share.swift's AirDrop service call. The generic sharing
// picker is left out: it needs a key window, and the notch panel never becomes one.

import AppKit

/// Hands files to the system's AirDrop window.
@MainActor
enum ShelfShare {
    static var isAirDropAvailable: Bool {
        NSSharingService(named: .sendViaAirDrop) != nil
    }

    static func canAirDrop(_ urls: [URL]) -> Bool {
        NSSharingService(named: .sendViaAirDrop)?.canPerform(withItems: urls) ?? false
    }

    /// Opens AirDrop with the files; `false` when the service is missing or refuses them.
    @discardableResult
    static func airDrop(_ urls: [URL]) -> Bool {
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else { return false }
        service.perform(withItems: urls)
        return true
    }
}
