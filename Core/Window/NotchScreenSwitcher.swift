import AppKit
import SwiftUI

/// Strip along the bottom of the expanded card: one pill per screen the notch can show, the active
/// one named so it is always clear which screen you are looking at. Pills carry the real icon of
/// the app a module speaks for, which makes the strip a live list of what is running.
struct NotchScreenSwitcher: View {
    let screens: [ModuleScreen]
    let activeID: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 5) {
            ForEach(screens) { screen in
                NotchScreenPill(screen: screen, isActive: screen.id == activeID) { onSelect(screen.id) }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct NotchScreenPill: View {
    let screen: ModuleScreen
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 5) {
            icon
            if isActive {
                Text(screen.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white.opacity(isActive ? 1 : (isHovering ? 0.9 : 0.55)))
        .padding(.horizontal, isActive ? 8 : 5)
        .frame(height: NotchLayout.switcherHeight - 6)
        .background(.white.opacity(isActive ? 0.16 : (isHovering ? 0.09 : 0)), in: Capsule())
        .contentShape(Capsule())
        .onHover { isHovering = $0 }
        .notchTap(perform: action)
        .help(isActive ? "Showing \(screen.title)" : "Switch to \(screen.title)")
        .accessibilityLabel(screen.title)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var icon: some View {
        if let image = AppIconCache.icon(for: screen.appBundleIdentifier) {
            Image(nsImage: image)
                .resizable()
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: screen.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 14)
        }
    }
}

/// App icons for the switcher, resolved once per bundle id.
///
/// A SwiftUI body runs many times during a morph, and scanning the process list on each pass would
/// be wasteful, so both hits and misses are remembered. An app's icon does not change while it is
/// installed, and a running app is preferred only because its icon is already in memory.
@MainActor
enum AppIconCache {
    private static var icons: [String: NSImage?] = [:]

    static func icon(for bundleIdentifier: String?) -> NSImage? {
        guard let bundleIdentifier else { return nil }
        if let cached = icons[bundleIdentifier] { return cached }
        let icon = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first?.icon
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
        icons[bundleIdentifier] = icon
        return icon
    }
}
