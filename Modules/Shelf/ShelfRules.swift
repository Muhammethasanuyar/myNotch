import CoreGraphics
import Foundation

/// The two places a drop can land on the open card.
nonisolated enum ShelfDropZone: Equatable, Sendable {
    case airDrop
    case shelf
}

/// Pure decisions of the shelf: when it counts as live, what expires, how things are named.
nonisolated enum ShelfRules {
    /// How long after a drop the shelf holds the compact strip before it goes quiet again.
    static let liveWindow: TimeInterval = 120
    /// The leading part of the card that is the AirDrop target, as a fraction of its width.
    static let airDropZoneFraction: CGFloat = 0.3
    static let defaultKeepInterval: TimeInterval = 86_400
    /// Offered retention periods, in seconds; `0` keeps files until removed by hand.
    static let keepIntervalChoices: [TimeInterval] = [3600, 43_200, 86_400, 172_800, 604_800, 0]
    /// Compact badge caps here; the card shows the real count.
    static let badgeCap = 9

    /// Live for a while after a drop so the compact strip shows what just landed; idle otherwise,
    /// so a full shelf never keeps the notch busy all day.
    static func activity(itemCount: Int, lastDropAt: Date?, now: Date) -> ModuleActivity {
        guard itemCount > 0, let lastDropAt, now.timeIntervalSince(lastDropAt) < liveWindow else { return .idle }
        return .live
    }

    /// When the live spell after `lastDropAt` ends.
    static func liveUntil(lastDropAt: Date?) -> Date? {
        lastDropAt.map { $0.addingTimeInterval(liveWindow) }
    }

    /// `keepInterval <= 0` means forever: the user's files are never removed on a timer.
    static func shouldPurge(addedAt: Date, now: Date, keepInterval: TimeInterval) -> Bool {
        keepInterval > 0 && now.timeIntervalSince(addedAt) >= keepInterval
    }

    static func expiry(addedAt: Date, keepInterval: TimeInterval) -> Date? {
        keepInterval > 0 ? addedAt.addingTimeInterval(keepInterval) : nil
    }

    /// A name not yet on the shelf: `report.pdf` → `report 2.pdf`, `report 3.pdf`, …
    static func uniqueFileName(_ name: String, existing: Set<String>) -> String {
        guard existing.contains(name) else { return name }
        let url = URL(fileURLWithPath: name)
        let ext = url.pathExtension
        let stem = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
        var counter = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) \(counter)" : "\(stem) \(counter).\(ext)"
            if !existing.contains(candidate) { return candidate }
            counter += 1
        }
    }

    /// Which target a drop at this point of the card hits; a drop with no card showing goes to the shelf.
    static func zone(unitPoint: CGPoint?) -> ShelfDropZone {
        guard let unitPoint else { return .shelf }
        return unitPoint.x < airDropZoneFraction ? .airDrop : .shelf
    }

    static func badgeText(count: Int) -> String {
        count > badgeCap ? "\(badgeCap)+" : String(count)
    }

    static func formatBytes(_ bytes: Int64, locale: Locale = .current) -> String {
        bytes.formatted(.byteCount(style: .file).locale(locale))
    }

    /// The offered period closest to `value`; anything at or below zero is "forever".
    static func snappedKeepInterval(_ value: TimeInterval) -> TimeInterval {
        guard value > 0 else { return 0 }
        return keepIntervalChoices.filter { $0 > 0 }.min { abs($0 - value) < abs($1 - value) } ?? defaultKeepInterval
    }

    static func keepIntervalTitle(_ interval: TimeInterval, bundle: Bundle = .main) -> String {
        switch interval {
        case ...0: String(localized: "shelf.keep.forever", defaultValue: "Until removed", bundle: bundle)
        case 3600: String(localized: "shelf.keep.hour", defaultValue: "1 hour", bundle: bundle)
        case 43_200: String(localized: "shelf.keep.hours12", defaultValue: "12 hours", bundle: bundle)
        case 86_400: String(localized: "shelf.keep.day", defaultValue: "1 day", bundle: bundle)
        case 172_800: String(localized: "shelf.keep.days2", defaultValue: "2 days", bundle: bundle)
        case 604_800: String(localized: "shelf.keep.week", defaultValue: "1 week", bundle: bundle)
        default: Duration.seconds(interval).formatted(.units(allowed: [.days, .hours], width: .wide))
        }
    }

    /// Newest first.
    static func sorted(_ items: [ShelfItem]) -> [ShelfItem] {
        items.sorted { $0.record.addedAt > $1.record.addedAt }
    }

    static func dropEvent(count: Int, moduleID: String, bundle: Bundle = .main) -> NotchEvent {
        let title = count == 1
            ? String(localized: "shelf.event.dropped.one", defaultValue: "1 file on the shelf", bundle: bundle)
            : String(localized: "shelf.event.dropped.many", defaultValue: "\(count) files on the shelf", bundle: bundle)
        return NotchEvent(moduleID: moduleID, title: title, symbolName: "tray.and.arrow.down.fill", duration: 2)
    }

    static func airDropEvent(count: Int, moduleID: String, bundle: Bundle = .main) -> NotchEvent {
        let title = count == 1
            ? String(localized: "shelf.event.airdrop.one", defaultValue: "Sending 1 file via AirDrop", bundle: bundle)
            : String(localized: "shelf.event.airdrop.many", defaultValue: "Sending \(count) files via AirDrop", bundle: bundle)
        return NotchEvent(moduleID: moduleID, title: title, symbolName: "dot.radiowaves.right", duration: 2)
    }
}
