import SwiftUI

/// Colours of the pomodoro module: a warm red for focus, a cool green for breaks.
enum PomodoroStyle {
    static let focus = Color(red: 0.93, green: 0.42, blue: 0.38)
    static let rest = Color(red: 0.36, green: 0.78, blue: 0.62)

    static func color(for phase: PomodoroPhase) -> Color {
        phase.isBreak ? rest : focus
    }

    static func symbol(for phase: PomodoroPhase) -> String {
        phase.isBreak ? "cup.and.saucer.fill" : "timer"
    }
}

/// Compact leading wing: the ring with the phase glyph inside it.
struct PomodoroCompactLeading: View {
    let timer: PomodoroTimer
    @Environment(\.wingContentSize) private var size

    var body: some View {
        let remaining = timer.remaining()
        ZStack {
            CountdownArc(
                fraction: PomodoroRules.fractionRemaining(remaining: remaining, total: timer.phaseLength),
                runningRemaining: timer.isRunning ? remaining : nil,
                runID: timer.snapshot.endDate,
                color: PomodoroStyle.color(for: timer.phase),
                lineWidth: max(2, size * 0.12)
            )
            Image(systemName: PomodoroStyle.symbol(for: timer.phase))
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(PomodoroStyle.color(for: timer.phase))
        }
        .frame(width: size, height: size)
    }
}

/// Compact trailing wing: the minutes left, updated on the minute — the ring shows the seconds.
struct PomodoroCompactTrailing: View {
    let timer: PomodoroTimer
    @Environment(\.wingContentSize) private var size

    var body: some View {
        if let endDate = timer.snapshot.endDate {
            // Ticks aligned to the countdown's own minute boundaries, only while this wing is on screen.
            TimelineView(.periodic(from: endDate, by: 60)) { context in
                label(PomodoroRules.remaining(endDate: endDate, now: context.date))
            }
        } else {
            label(timer.remaining())
        }
    }

    private func label(_ remaining: TimeInterval) -> some View {
        let minutes = Int((max(0, remaining) / 60).rounded(.up))
        return Text(Duration.seconds(minutes * 60).formatted(.units(allowed: [.minutes], width: .narrow)))
            .font(.system(size: size * 0.5, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(PomodoroStyle.color(for: timer.phase))
            .contentTransition(.numericText())
            .lineLimit(1)
    }
}

/// What the cursor is resting on inside the card.
private enum PomodoroFocus: Hashable {
    case ring
    case phase
    case cycles
    case controls
}

/// The card: a large ring with the time left, the phase and the finished blocks beside it, and
/// the three controls — start/pause, skip, reset — each answering the first click.
struct PomodoroExpandedView: View {
    let timer: PomodoroTimer

    @State private var focus: PomodoroFocus?
    @State private var appeared = false

    var body: some View {
        let phase = timer.phase
        let color = PomodoroStyle.color(for: phase)
        HStack(alignment: .center, spacing: 22) {
            ring(color: color)
                .frame(width: 104, height: 104)
                .spotlight(PomodoroFocus.ring, focus: $focus, accent: color)
                .reveal(appeared, index: 0)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: PomodoroStyle.symbol(for: phase))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(color)
                    Text(PomodoroRules.title(for: phase))
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                }
                .spotlight(PomodoroFocus.phase, focus: $focus, accent: color)
                .reveal(appeared, index: 1)

                cycleDots(color: color)
                    .spotlight(PomodoroFocus.cycles, focus: $focus, accent: color)
                    .reveal(appeared, index: 2)

                controls(color: color)
                    .spotlight(PomodoroFocus.controls, focus: $focus, accent: color)
                    .reveal(appeared, index: 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomLeading) {
            if let focus {
                NotchExplanationBubble(text: explanation(for: focus), accent: color)
                    .padding(.bottom, 2)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: focus)
        .onAppear { appeared = true }
    }

    private func ring(color: Color) -> some View {
        let remaining = timer.remaining()
        return ZStack {
            CountdownArc(
                fraction: PomodoroRules.fractionRemaining(remaining: remaining, total: timer.phaseLength),
                runningRemaining: timer.isRunning ? remaining : nil,
                runID: timer.snapshot.endDate,
                color: color,
                lineWidth: 7
            )
            if let endDate = timer.snapshot.endDate {
                // Seconds only while the card is open; the ring itself needs no ticks.
                TimelineView(.periodic(from: endDate, by: 1)) { context in
                    timeLabel(PomodoroRules.remaining(endDate: endDate, now: context.date))
                }
            } else {
                timeLabel(remaining)
            }
        }
    }

    private func timeLabel(_ remaining: TimeInterval) -> some View {
        Text(PomodoroRules.format(remaining))
            .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
            .contentTransition(.numericText())
    }

    /// One dot per work block in the current round; filled once done.
    private func cycleDots(color: Color) -> some View {
        let every = max(1, timer.config.longBreakEvery)
        let done = timer.snapshot.completedWorkCount % every
        let inRound = timer.snapshot.completedWorkCount > 0 && done == 0 && timer.phase == .longBreak ? every : done
        return HStack(spacing: 6) {
            ForEach(0..<every, id: \.self) { index in
                Circle()
                    .fill(index < inRound ? color : .white.opacity(0.18))
                    .frame(width: 8, height: 8)
            }
            Text(L("pomodoro.cycles.caption", "\(timer.snapshot.completedWorkCount) done"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .contentTransition(.numericText())
        }
    }

    private func controls(color: Color) -> some View {
        HStack(spacing: 8) {
            controlButton(timer.isRunning ? "pause.fill" : "play.fill", prominent: true, color: color) { timer.toggle() }
            controlButton("forward.end.fill", prominent: false, color: color) { timer.skip() }
                .opacity(timer.phase == .idle ? 0.35 : 1)
            controlButton("arrow.counterclockwise", prominent: false, color: color) { timer.reset() }
                .opacity(timer.phase == .idle ? 0.35 : 1)
        }
    }

    private func controlButton(_ symbol: String, prominent: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(prominent ? .black : .white)
            .frame(width: prominent ? 44 : 34, height: 28)
            .background(prominent ? color : .white.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
            .notchTap(perform: action)
    }

    private func explanation(for focus: PomodoroFocus) -> String {
        switch focus {
        case .ring: return PomodoroRules.ringExplanation(timer.snapshot, config: timer.config)
        case .phase: return PomodoroRules.title(for: timer.phase) + " — " + L("pomodoro.explain.phase", "focus blocks and breaks alternate; the lengths are in Settings.")
        case .cycles: return PomodoroRules.cycleExplanation(completed: timer.snapshot.completedWorkCount, config: timer.config)
        case .controls: return L("pomodoro.explain.controls", "Start or pause, skip to the next phase, or reset the whole cycle.")
        }
    }
}
