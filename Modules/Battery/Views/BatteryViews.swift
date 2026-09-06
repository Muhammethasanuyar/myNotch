import SwiftUI

/// Colours of the battery module.
enum BatteryStyle {
    static let healthy = Color(red: 0.36, green: 0.8, blue: 0.5)
    static let low = Color.orange
    static let critical = Color.red

    static func color(level: Int) -> Color {
        switch level {
        case 2: return critical
        case 1: return low
        default: return healthy
        }
    }
}

/// Compact leading wing: a breathing bolt while charging, a red battery glyph while low.
struct BatteryCompactLeading: View {
    let service: BatteryService
    @Environment(\.wingContentSize) private var size

    var body: some View {
        if let snapshot = service.snapshot {
            let level = BatteryRules.level(snapshot, thresholds: service.thresholds)
            PulsingSymbol(
                systemName: snapshot.isCharging ? "bolt.fill" : (level == 2 ? "battery.0percent" : "battery.25percent"),
                pointSize: size * 0.65,
                weight: .bold,
                color: snapshot.isCharging ? BatteryStyle.healthy : BatteryStyle.color(level: level),
                isActive: snapshot.isCharging
            )
        }
    }
}

/// Compact trailing wing: the percentage, rolling as it changes.
struct BatteryCompactTrailing: View {
    let service: BatteryService
    @Environment(\.wingContentSize) private var size

    var body: some View {
        if let snapshot = service.snapshot {
            Text(BatteryRules.percentText(snapshot))
                .font(.system(size: size * 0.5, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(snapshot.isCharging ? BatteryStyle.healthy : BatteryStyle.color(level: BatteryRules.level(snapshot, thresholds: service.thresholds)))
                .contentTransition(.numericText())
                .animation(.default, value: snapshot.percentage)
                .lineLimit(1)
        }
    }
}

/// What the cursor is resting on inside the card.
private enum BatteryFocus: Hashable {
    case gauge
    case status
    case estimate
    case lowPower
}

/// The card: a large gauge that fills to the charge, and beside it the state, the estimate and
/// Low Power Mode — each lifting under the cursor with a sentence that explains it.
struct BatteryExpandedView: View {
    let service: BatteryService

    @State private var focus: BatteryFocus?
    @State private var appeared = false

    var body: some View {
        Group {
            if let snapshot = service.snapshot {
                content(snapshot)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "battery.100percent")
                        .font(.title2)
                    Text(L("battery.none", "No battery in this Mac"))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(.white)
        .onAppear { appeared = true }
    }

    private func content(_ snapshot: BatterySnapshot) -> some View {
        let level = BatteryRules.level(snapshot, thresholds: service.thresholds)
        return HStack(alignment: .center, spacing: 18) {
            BatteryGauge(percentage: snapshot.percentage, color: snapshot.isCharging ? BatteryStyle.healthy : BatteryStyle.color(level: level), isCharging: snapshot.isCharging)
                .frame(width: 170, height: 78)
                .spotlight(BatteryFocus.gauge, focus: $focus, accent: BatteryStyle.color(level: level))
                .reveal(appeared, index: 0)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(BatteryRules.percentText(snapshot))
                        .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                    Text(BatteryRules.statusTitle(snapshot))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                .spotlight(BatteryFocus.status, focus: $focus, accent: BatteryStyle.healthy)
                .reveal(appeared, index: 1)

                // A full battery on power has no estimate to give; the row only shows while a
                // charge or a discharge is under way.
                if snapshot.isCharging || !snapshot.isPluggedIn {
                    HStack(spacing: 6) {
                        Image(systemName: snapshot.isCharging ? "clock.badge.checkmark" : "clock")
                            .font(.system(size: 11, weight: .semibold))
                        Text(BatteryRules.estimate(snapshot) ?? L("battery.estimate.pending", "Estimating…"))
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .contentTransition(.numericText())
                    }
                    .foregroundStyle(.white.opacity(0.75))
                    .spotlight(BatteryFocus.estimate, focus: $focus, accent: BatteryStyle.healthy)
                    .reveal(appeared, index: 2)
                }

                HStack(spacing: 6) {
                    Image(systemName: snapshot.isLowPowerMode ? "leaf.fill" : "leaf")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(snapshot.isLowPowerMode ? BatteryStyle.healthy : .white.opacity(0.4))
                    Text(snapshot.isLowPowerMode ? L("battery.lowPower.on", "Low Power Mode") : L("battery.lowPower.off", "Full power"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .spotlight(BatteryFocus.lowPower, focus: $focus, accent: BatteryStyle.healthy)
                .reveal(appeared, index: 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomLeading) {
            if let focus {
                NotchExplanationBubble(text: explanation(for: focus, snapshot: snapshot), accent: BatteryStyle.color(level: level))
                    .padding(.bottom, 2)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: focus)
    }

    private func explanation(for focus: BatteryFocus, snapshot: BatterySnapshot) -> String {
        switch focus {
        case .gauge: return BatteryRules.gaugeExplanation(snapshot, thresholds: service.thresholds)
        case .status: return BatteryRules.statusExplanation(snapshot)
        case .estimate:
            return BatteryRules.estimate(snapshot) == nil
                ? L("battery.explain.estimating", "macOS needs a few minutes of steady use before it commits to an estimate.")
                : BatteryRules.statusExplanation(snapshot)
        case .lowPower: return BatteryRules.lowPowerExplanation(snapshot)
        }
    }
}

/// A battery outline whose fill follows the charge; the fill glides when the level changes and a
/// bolt breathes over it while charging (Core Animation, so nothing renders per frame).
struct BatteryGauge: View {
    let percentage: Int
    let color: Color
    let isCharging: Bool

    var body: some View {
        GeometryReader { proxy in
            let nub = proxy.size.width * 0.05
            let bodyWidth = proxy.size.width - nub - 2
            let inset: CGFloat = 5
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.55), lineWidth: 3)
                    .frame(width: bodyWidth)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(.white.opacity(0.55))
                    .frame(width: nub, height: proxy.size.height * 0.35)
                    .offset(x: bodyWidth + 2)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color)
                    .frame(width: max(0, (bodyWidth - 2 * inset) * CGFloat(percentage) / 100), height: proxy.size.height - 2 * inset)
                    .padding(.leading, inset)
                    .animation(.spring(response: 0.9, dampingFraction: 0.85), value: percentage)
                    .animation(.easeInOut(duration: 0.4), value: color)
                if isCharging {
                    PulsingSymbol(systemName: "bolt.fill", pointSize: proxy.size.height * 0.5, weight: .bold, color: .white.opacity(0.95), isActive: true)
                        .frame(width: bodyWidth)
                        .transition(.opacity)
                }
            }
            .frame(height: proxy.size.height)
        }
    }
}
