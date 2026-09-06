import SwiftUI

enum VolumeStyle {
    static let accent = Color(red: 0.98, green: 0.82, blue: 0.35)
}

/// The popup: glyph, a sixteen-segment bar, the level. Reads the service directly so a burst of
/// presses moves the bar in place instead of replacing the popup.
struct VolumePopupView: View {
    let service: VolumeService

    var body: some View {
        let snapshot = service.snapshot ?? VolumeSnapshot(volume: 0, isMuted: false, hasVolumeControl: false, deviceName: "")
        HStack(spacing: 10) {
            Image(systemName: VolumeRules.symbolName(volume: snapshot.volume, isMuted: snapshot.isMuted))
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 20)
                .contentTransition(.symbolEffect(.replace))
            VolumeSegments(volume: snapshot.volume, isMuted: snapshot.isMuted, accent: VolumeStyle.accent)
                .frame(height: 8)
            Text(VolumeRules.levelText(snapshot))
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
                .frame(width: 44, alignment: .trailing)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: snapshot)
    }
}

/// Sixteen capsules, lit up to the level.
struct VolumeSegments: View {
    let volume: Float
    let isMuted: Bool
    let accent: Color
    var count = VolumeRules.barSegmentCount

    var body: some View {
        let lit = VolumeRules.barSegments(volume, isMuted: isMuted, count: count)
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index < lit ? accent : .white.opacity(0.18))
            }
        }
    }
}

/// What the cursor is resting on inside the card.
private enum VolumeFocus: Hashable {
    case level
    case mute
    case device
    case mode
}

/// The card: the level as a wide bar with the mute button, the device, and how the sound keys are
/// handled — with the Accessibility step when the replacement is waiting for it.
struct VolumeExpandedView: View {
    let service: VolumeService

    @State private var focus: VolumeFocus?
    @State private var appeared = false

    var body: some View {
        let snapshot = service.snapshot ?? VolumeSnapshot(volume: 0, isMuted: false, hasVolumeControl: false, deviceName: L("volume.noDevice", "No output device"))
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: VolumeRules.symbolName(volume: snapshot.volume, isMuted: snapshot.isMuted))
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 30)
                    .contentTransition(.symbolEffect(.replace))
                    .spotlight(VolumeFocus.mute, focus: $focus, accent: VolumeStyle.accent)
                    .notchTap(isEnabled: snapshot.hasVolumeControl) { service.toggleMute() }
                VolumeSegments(volume: snapshot.volume, isMuted: snapshot.isMuted, accent: VolumeStyle.accent, count: 32)
                    .frame(height: 14)
                    .spotlight(VolumeFocus.level, focus: $focus, accent: VolumeStyle.accent)
                Text(VolumeRules.levelText(snapshot))
                    .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                    .frame(width: 64, alignment: .trailing)
            }
            .reveal(appeared, index: 0)

            HStack(spacing: 14) {
                Label(snapshot.deviceName, systemImage: "hifispeaker.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .spotlight(VolumeFocus.device, focus: $focus, accent: VolumeStyle.accent)
                Spacer(minLength: 0)
                modeBadge
                    .spotlight(VolumeFocus.mode, focus: $focus, accent: VolumeStyle.accent)
            }
            .reveal(appeared, index: 1)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .overlay(alignment: .bottomLeading) {
            if let focus {
                NotchExplanationBubble(text: explanation(for: focus, snapshot: snapshot), accent: VolumeStyle.accent)
                    .padding(.bottom, 2)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: focus)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: snapshot)
        .onAppear { appeared = true }
    }

    private var modeBadge: some View {
        let (symbol, text, color): (String, String, Color) = switch service.tapState {
        case .off: ("keyboard", L("volume.mode.system", "System HUD"), .white.opacity(0.6))
        case .needsPermission: ("lock.fill", L("volume.mode.permission", "Needs Accessibility"), .orange)
        case .running: ("keyboard.badge.ellipsis", L("volume.mode.notch", "Keys go to the notch"), VolumeStyle.accent)
        case .failed: ("exclamationmark.triangle.fill", L("volume.mode.failed", "Tap failed"), .red)
        }
        return HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.14), in: Capsule())
        .notchTap(isEnabled: service.tapState == .needsPermission) { service.requestAccessibility() }
    }

    private func explanation(for focus: VolumeFocus, snapshot: VolumeSnapshot) -> String {
        switch focus {
        case .level:
            return snapshot.hasVolumeControl
                ? L("volume.explain.level", "The output level in sixteenths, as the volume keys move it. It follows changes made anywhere.")
                : L("volume.explain.noControl", "This device has no volume of its own; the keys keep their system behaviour here.")
        case .mute:
            return L("volume.explain.mute", "Tap to mute or unmute.")
        case .device:
            return L("volume.explain.device", "The current output. Switching AirPods or a display changes it here too.")
        case .mode:
            switch service.tapState {
            case .off: return L("volume.explain.mode.off", "macOS shows its own HUD; the notch adds a short popup. Settings → Sound can hand the keys to the notch.")
            case .needsPermission: return L("volume.explain.mode.permission", "Taking the keys needs the Accessibility permission. Tap to ask; the grant resets when the app is rebuilt or updated with a new signature.")
            case .running: return L("volume.explain.mode.running", "Volume and mute keys come here first; brightness keys stay with macOS. Shift plays the feedback sound, Option-Shift moves in quarter steps.")
            case .failed(let message): return L("volume.explain.mode.failed", "The event tap could not start: \(message)")
            }
        }
    }
}
