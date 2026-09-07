import SwiftUI

enum AudioDeviceStyle {
    static let accent = Color(red: 0.55, green: 0.85, blue: 0.95)
}

/// What the cursor is resting on inside the card.
private enum AudioDeviceFocus: Hashable {
    case device
    case transport
    case latency
    case battery
}

/// The card: the device with its glyph, transport and output latency, and the AirPods battery as
/// three small bars when the registry offers it.
struct AudioDeviceExpandedView: View {
    let service: AudioDeviceService

    @State private var focus: AudioDeviceFocus?
    @State private var appeared = false

    var body: some View {
        Group {
            if let output = service.output {
                content(output)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "speaker.slash")
                        .font(.title2)
                    Text(L("audioDevice.none", "No output device"))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(.white)
        .onAppear { appeared = true }
    }

    private func content(_ output: AudioOutputInfo) -> some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: AudioDeviceRules.symbolName(for: output))
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(AudioDeviceStyle.accent)
                .frame(width: 70)
                .contentTransition(.symbolEffect(.replace))
                .spotlight(AudioDeviceFocus.device, focus: $focus, accent: AudioDeviceStyle.accent)
                .reveal(appeared, index: 0)

            VStack(alignment: .leading, spacing: 8) {
                Text(output.name)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .spotlight(AudioDeviceFocus.device, focus: $focus, accent: AudioDeviceStyle.accent)
                    .reveal(appeared, index: 1)
                HStack(spacing: 12) {
                    Label(AudioDeviceRules.transportName(output.transport), systemImage: "cable.connector")
                        .spotlight(AudioDeviceFocus.transport, focus: $focus, accent: AudioDeviceStyle.accent)
                    if let latency = service.outputLatency {
                        Label(latencyText(latency), systemImage: "timer")
                            .spotlight(AudioDeviceFocus.latency, focus: $focus, accent: AudioDeviceStyle.accent)
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .reveal(appeared, index: 2)
                if let battery = service.battery, !battery.isEmpty {
                    HStack(spacing: 10) {
                        batteryBar(L("audioDevice.left", "L"), battery.left)
                        batteryBar(L("audioDevice.right", "R"), battery.right)
                        batteryBar(L("audioDevice.case", "Case"), battery.caseLevel)
                    }
                    .spotlight(AudioDeviceFocus.battery, focus: $focus, accent: AudioDeviceStyle.accent)
                    .reveal(appeared, index: 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomLeading) {
            if let focus {
                NotchExplanationBubble(text: explanation(for: focus), accent: AudioDeviceStyle.accent)
                    .padding(.bottom, 2)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: focus)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: service.battery)
    }

    @ViewBuilder
    private func batteryBar(_ label: String, _ percent: Int?) -> some View {
        if let percent {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(label) \(percent)%")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(width: 56, height: 5)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(percent <= 20 ? Color.red : AudioDeviceStyle.accent)
                            .frame(width: 56 * CGFloat(percent) / 100)
                    }
            }
        }
    }

    private func latencyText(_ latency: TimeInterval) -> String {
        L("audioDevice.latency", "\(Int((latency * 1000).rounded())) ms")
    }

    private func explanation(for focus: AudioDeviceFocus) -> String {
        switch focus {
        case .device: L("audioDevice.explain.device", "Where the sound goes right now. A popup marks each switch away from the built-in speakers.")
        case .transport: L("audioDevice.explain.transport", "How the device is connected. Bluetooth devices can also report their battery.")
        case .latency: L("audioDevice.explain.latency", "Output latency as Core Audio reports it; the lyrics use the same number to stay in time on Bluetooth.")
        case .battery: L("audioDevice.explain.battery", "Read from the IORegistry; AirPods report it a few seconds after connecting and only while connected.")
        }
    }
}
