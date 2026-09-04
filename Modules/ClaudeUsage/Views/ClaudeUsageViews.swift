import SwiftUI

// Adapted from https://github.com/stevemcqueenz/claude-notch-tracker (MIT): the trimmed-circle ring
// rotated to start at twelve o'clock, coloured by threshold.

/// Anthropic's warm orange, used for the mark and the calm ring.
enum ClaudeStyle {
    static let accent = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let warning = Color.orange
    static let critical = Color.red

    static func ringColor(level: Int) -> Color {
        switch level {
        case 2: return critical
        case 1: return warning
        default: return accent
        }
    }
}

/// Compact leading wing: the mark, pulsing while Claude works.
struct ClaudeCompactLeading: View {
    let service: ClaudeUsageService
    let namespace: Namespace.ID

    var body: some View {
        Image(systemName: "asterisk")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(service.isWorking ? ClaudeStyle.accent : .white.opacity(0.5))
            .symbolEffect(.pulse, options: .repeating, isActive: service.isWorking)
            .matchedGeometryEffect(id: ClaudeUsageModule.markID, in: namespace)
    }
}

/// Compact trailing wing: the 5-hour percentage, or today's cost when the limits are unknown.
struct ClaudeCompactTrailing: View {
    let service: ClaudeUsageService

    var body: some View {
        if let label = ClaudeUsageRules.compactLabel(fiveHour: service.snapshot?.fiveHour, todayCost: service.cost?.today?.totalCost) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(service.isStale ? 0.5 : 0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// A limit as two arcs: the thick one is how much of the allowance is used, the thin one outside it
/// how much of the window has passed — so pace is visible without a word. Both arcs sweep in when
/// the card opens and glide when the numbers change; the 5-hour arc breathes while Claude works.
struct UsageRing: View {
    let window: UsageWindow?
    let kind: UsageWindowKind
    let thresholds: UsageThresholds
    let now: Date
    var isWorking = false
    var diameter: CGFloat = 62
    var dimmed = false

    @State private var appeared = false
    @State private var glowing = false

    private var usage: Double { appeared ? (window?.utilization ?? 0) : 0 }
    private var elapsed: Double { appeared ? (window?.elapsedFraction(kind: kind, at: now) ?? 0) : 0 }
    private var color: Color {
        ClaudeStyle.ringColor(level: ClaudeUsageRules.level(for: window?.utilization ?? 0, thresholds: thresholds))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: 2)
            Circle()
                .trim(from: 0, to: elapsed)
                .stroke(.white.opacity(0.4), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: 6)
                .padding(7)
            if window != nil {
                Circle()
                    .trim(from: 0, to: max(0.004, usage))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(7)
                    .shadow(color: color.opacity(glowing ? 0.65 : 0), radius: glowing ? 7 : 0)
            }
            VStack(spacing: -2) {
                Text(window.map { "\(Int(($0.utilization * 100).rounded()))%" } ?? "—")
                    .font(.system(size: diameter * 0.23, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text(kind.badge)
                    .font(.system(size: diameter * 0.13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
        .opacity(dimmed ? 0.5 : 1)
        .animation(.spring(response: 0.9, dampingFraction: 0.85), value: usage)
        .animation(.easeOut(duration: 0.7), value: elapsed)
        .animation(.easeInOut(duration: 0.4), value: color)
        .onAppear { appeared = true }
        .onChange(of: isWorking, initial: true) { _, working in
            // The consuming window breathes while tokens flow; a repeating animation stops the
            // moment the flag drops, and with the view when the card closes.
            if working {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { glowing = true }
            } else {
                withAnimation(.easeOut(duration: 0.3)) { glowing = false }
            }
        }
    }
}

/// What the cursor is resting on, so it can stand out and explain itself.
private enum DashboardFocus: Hashable {
    case ring(UsageWindowKind)
    case spend
    case tokens
    case pace
    case models
    case status
    case plan
    case working
}

/// The module's full interface, built to be read as shapes: two rings for the limits, icon chips for
/// today's numbers, a model split, a status dot. Everything moves — arcs sweep in, digits roll, the
/// mark pulses — and everything explains itself: rest the cursor on any indicator and it lifts
/// towards you while a line of plain text appears in the card. Words that stay on screen are kept
/// for what the user must do.
struct ClaudeDashboardView: View {
    let service: ClaudeUsageService
    let namespace: Namespace.ID

    @State private var focus: DashboardFocus?
    @State private var appeared = false

    var body: some View {
        // Every half minute, so the thin "time passed" arcs and countdowns keep moving while open.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(alignment: .top, spacing: 14) {
                rings(at: context.date)
                    .reveal(appeared, index: 0)
                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 1)
                    .padding(.vertical, 6)
                details(at: context.date)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { appeared = true }
    }

    // MARK: Rings

    private func rings(at now: Date) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ring(kind: .fiveHour, at: now)
            ring(kind: .sevenDay, at: now)
        }
    }

    private func ring(kind: UsageWindowKind, at now: Date) -> some View {
        let window = service.snapshot?[kind]
        let remaining = window?.remaining(at: now).map(ClaudeUsageRules.formatRemaining)
        return VStack(spacing: 6) {
            UsageRing(
                window: window,
                kind: kind,
                thresholds: service.thresholds,
                now: now,
                isWorking: kind == .fiveHour && service.isWorking,
                dimmed: service.isStale
            )
            HStack(spacing: 3) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 8, weight: .semibold))
                    .symbolEffect(.bounce, value: remaining)   // `.rotate` needs macOS 15
                Text(remaining ?? "—")
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .contentTransition(.numericText())
            }
            .foregroundStyle(.secondary)
        }
        .frame(width: 66)
        .spotlight(.ring(kind), focus: $focus)
    }

    // MARK: Details

    private func details(at now: Date) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            header
                .reveal(appeared, index: 1)
            statChips
                .reveal(appeared, index: 2)
            modelsRow
                .reveal(appeared, index: 3)
            Spacer(minLength: 0)
            footer
                .reveal(appeared, index: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottomLeading) {
            // Floats above the footer and never takes hits, so the indicator under the cursor
            // stays hovered while its explanation is up.
            if let focus {
                Text(explanation(for: focus, at: now))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(ClaudeStyle.accent.opacity(0.55), lineWidth: 1))
                    .padding(.bottom, 16)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .id(focus)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: focus)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "asterisk")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(service.isWorking ? ClaudeStyle.accent : .white.opacity(0.6))
                .symbolEffect(.pulse, options: .repeating, isActive: service.isWorking)
                .matchedGeometryEffect(id: ClaudeUsageModule.markID, in: namespace)
            Text("Claude Code")
                .font(.headline)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                if service.isWorking, let project = service.session?.customTitle ?? service.session?.projectName {
                    Text(project)
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                // A ripple that only runs while Claude writes; a still dot when it is quiet.
                Image(systemName: service.isWorking ? "ellipsis" : "circle.fill")
                    .font(.system(size: service.isWorking ? 12 : 6, weight: .bold))
                    .symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: service.isWorking)
                    .contentTransition(.symbolEffect(.replace))
            }
            .foregroundStyle(service.isWorking ? ClaudeStyle.accent : .white.opacity(0.35))
            .spotlight(.working, focus: $focus)
        }
        .animation(Anim.subtle, value: service.isWorking)
    }

    /// Today's numbers as icon chips: spend, tokens, and the pace of the current block. Each chip
    /// carries a one-word caption; the digits roll over as the numbers change.
    @ViewBuilder
    private var statChips: some View {
        HStack(alignment: .top, spacing: 6) {
            switch service.costState {
            case .ready:
                if let today = service.cost?.today {
                    statChip(.spend, "dollarsign.circle", value: costValue(for: today), caption: "spend", bounce: today.totalCost)
                    statChip(.tokens, "number", value: ClaudeUsageRules.formatTokens(today.totalTokens), caption: "tokens", bounce: Double(today.totalTokens))
                } else {
                    statChip(.spend, "dollarsign.circle", value: "0", caption: "spend", bounce: 0)
                }
                if let block = service.cost?.activeBlock, let rate = block.burnRate,
                   let burn = ClaudeUsageRules.burnDescription(
                       tokensPerMinute: rate.tokensPerMinuteForIndicator ?? rate.tokensPerMinute,
                       costPerHour: rate.costPerHour,
                       projectedCost: block.projection?.totalCost
                   ) {
                    statChip(.pace, "flame.fill", value: burn.value.replacingOccurrences(of: " tok/min", with: "/min"), caption: "pace",
                             bounce: rate.tokensPerMinute ?? 0, flicker: service.isWorking)
                }
            case .notInstalled:
                statChip(.spend, "arrow.down.circle", value: "ccusage", caption: "install", bounce: 0)
            case .failed:
                statChip(.spend, "exclamationmark.circle", value: "ccusage", caption: "failed", bounce: 0)
            case .unknown:
                EmptyView()
            }
        }
    }

    private func statChip(_ element: DashboardFocus, _ symbol: String, value: String, caption: String, bounce: Double, flicker: Bool = false) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(focus == element ? ClaudeStyle.accent : .secondary)
                    .symbolEffect(.bounce, value: bounce)
                    .symbolEffect(.pulse, options: .repeating, isActive: flicker)
                Text(value)
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(.white.opacity(focus == element ? 0.18 : 0.09), in: Capsule())
            Text(caption)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(focus == element ? .white : .white.opacity(0.4))
        }
        .lineLimit(1)
        .spotlight(element, focus: $focus)
    }

    /// ccusage prices from an offline table; a model it does not know comes out as $0, which is
    /// not free, so that shows as a dash and the explanation names the model.
    private func costValue(for today: CCUsageDay) -> String {
        if today.totalCost > 0 { return ClaudeUsageRules.formatCost(today.totalCost).replacingOccurrences(of: "$", with: "") }
        let unpriced = today.modelBreakdowns.contains { $0.cost == 0 && ($0.outputTokens > 0 || $0.inputTokens > 0) }
        return unpriced ? "—" : "0"
    }

    /// Which models did today's work: a dot and a name for one model, a segmented bar for several.
    @ViewBuilder
    private var modelsRow: some View {
        if let today = service.cost?.today {
            let shares = ModelShare.compute(today.modelBreakdowns)
            if shares.count > 1 {
                ModelShareBar(shares: shares, highlighted: focus == .models)
                    .spotlight(.models, focus: $focus)
            } else if let only = shares.first {
                HStack(spacing: 4) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(ClaudeStyle.accent)
                        .symbolEffect(.pulse, options: .repeating, isActive: service.isWorking)
                    Text(only.name)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(focus == .models ? .white : .secondary)
                }
                .spotlight(.models, focus: $focus)
            }
        }
    }

    /// A breathing dot says whether the numbers are fresh; words appear only when something needs doing.
    private var footer: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(statusColor)
                    .shadow(color: statusColor.opacity(0.7), radius: 3)
                    .symbolEffect(.pulse, options: .repeating, isActive: true)
                if let action = actionText {
                    Text(action)
                        .font(.system(size: 10))
                        .foregroundStyle(ClaudeStyle.warning)
                        .lineLimit(1)
                }
            }
            .spotlight(.status, focus: $focus)
            Spacer(minLength: 4)
            if let plan = service.subscriptionType, !plan.isEmpty {
                Text(plan.capitalized)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(focus == .plan ? .white : .secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.white.opacity(focus == .plan ? 0.22 : 0.12), in: Capsule())
                    .spotlight(.plan, focus: $focus)
            }
        }
        .animation(Anim.subtle, value: statusColor)
    }

    private var statusColor: Color {
        switch service.auth {
        case .ok: return service.isStale ? ClaudeStyle.warning : Color(red: 0.36, green: 0.8, blue: 0.5)
        case .rateLimited, .unreachable: return ClaudeStyle.warning
        case .signedOut, .tokenExpired, .reauthRequired: return ClaudeStyle.critical
        }
    }

    /// Something the user must do; `nil` when there is nothing to say.
    private var actionText: String? {
        switch service.auth {
        case .ok, .rateLimited, .unreachable: return nil
        case .signedOut: return "Sign in with `claude`"
        case .tokenExpired: return "Run `claude` to refresh the token"
        case .reauthRequired: return "Run `claude /login`"
        }
    }

    // MARK: Explanations

    private func explanation(for focus: DashboardFocus, at now: Date) -> String {
        switch focus {
        case .ring(let kind):
            return ClaudeUsageRules.ringExplanation(kind: kind, window: service.snapshot?[kind], now: now)
        case .spend:
            switch service.costState {
            case .notInstalled: return "Spend and tokens come from the ccusage tool. Install it with `brew install ccusage` (or `npm i -g ccusage`)."
            case .failed: return "ccusage could not produce a report; the log (subsystem com.emre.mynotch) has the error."
            default: return service.cost?.today.map(ClaudeUsageRules.spendExplanation) ?? "Nothing has been spent today."
            }
        case .tokens:
            return service.cost?.today.map(ClaudeUsageRules.tokensExplanation) ?? "No tokens used today."
        case .pace:
            guard let block = service.cost?.activeBlock else { return "No 5-hour block is active." }
            return ClaudeUsageRules.paceExplanation(
                tokensPerMinute: block.burnRate?.tokensPerMinuteForIndicator ?? block.burnRate?.tokensPerMinute,
                costPerHour: block.burnRate?.costPerHour,
                projectedCost: block.projection?.totalCost,
                blockEnd: block.endTime,
                now: now
            )
        case .models:
            let today = service.cost?.today
            return ClaudeUsageRules.modelsExplanation(shares: ModelShare.compute(today?.modelBreakdowns ?? []), bySpend: (today?.totalCost ?? 0) > 0)
        case .status:
            return statusExplanation(at: now)
        case .plan:
            return "Your Claude plan (\(service.subscriptionType?.capitalized ?? "unknown")), as recorded in Claude Code's sign-in on this Mac."
        case .working:
            if service.isWorking {
                let project = service.session?.customTitle ?? service.session?.projectName
                return "Claude Code is writing to a session log right now" + (project.map { " in \($0)" } ?? "") + "."
            }
            return service.hasLogs
                ? "Claude Code is quiet. It counts as working while a session log changed within the last ten seconds."
                : "No Claude Code session logs were found on this Mac yet."
        }
    }

    private func statusExplanation(at now: Date) -> String {
        switch service.auth {
        case .ok:
            guard let fetched = service.snapshot?.fetchedAt else { return "Waiting for Anthropic's first reading of your limits." }
            let age = ClaudeUsageRules.formatRemaining(now.timeIntervalSince(fetched))
            return "Limits read from Anthropic \(age) ago; they refresh every five minutes." + (service.isStale ? " This reading is older than fifteen minutes." : "")
        case .signedOut: return "No Claude Code sign-in was found on this Mac. Run `claude` in Terminal once and the limits appear."
        case .tokenExpired: return "The access token has expired. Running `claude` refreshes it; nothing is written by MyNotch."
        case .reauthRequired: return "The token lacks a scope the usage endpoint now needs; only `claude /login` can grant it."
        case .rateLimited(let until): return "Anthropic rate-limited the usage endpoint. The next attempt is at \(until.formatted(date: .omitted, time: .shortened))."
        case .unreachable: return service.snapshot == nil ? "Anthropic could not be reached." : "Anthropic could not be reached; the last reading is shown."
        }
    }
}

// MARK: - Motion helpers

/// Lifts an indicator towards the cursor and tells the card what is being looked at.
private struct Spotlight: ViewModifier {
    let element: DashboardFocus
    @Binding var focus: DashboardFocus?

    func body(content: Content) -> some View {
        let active = focus == element
        content
            .scaleEffect(active ? 1.08 : 1)
            .shadow(color: ClaudeStyle.accent.opacity(active ? 0.45 : 0), radius: active ? 8 : 0)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    focus = element
                } else if focus == element {
                    focus = nil
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: active)
    }
}

/// Fades and slides an element in when the card opens, each a beat after the last.
private struct Reveal: ViewModifier {
    let appeared: Bool
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(Double(index) * 0.07), value: appeared)
    }
}

private extension View {
    func spotlight(_ element: DashboardFocus, focus: Binding<DashboardFocus?>) -> some View {
        modifier(Spotlight(element: element, focus: focus))
    }

    func reveal(_ appeared: Bool, index: Int) -> some View {
        modifier(Reveal(appeared: appeared, index: index))
    }
}

/// Colours for the model split, in share order.
private enum ModelShareStyle {
    static func color(_ index: Int) -> Color {
        switch index {
        case 0: return ClaudeStyle.accent
        case 1: return .white.opacity(0.55)
        default: return .white.opacity(0.3)
        }
    }
}

/// A thin bar split into one segment per model, each segment's name under it. Drawn only for two
/// or more models — a single segment would just look like a meter stuck at full. The segments
/// settle into their shares when the card opens.
private struct ModelShareBar: View {
    let shares: [ModelShare]
    var highlighted = false

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(Array(shares.enumerated()), id: \.offset) { index, share in
                        Capsule()
                            .fill(ModelShareStyle.color(index))
                            .frame(width: max(3, (proxy.size.width - 2 * CGFloat(shares.count - 1)) * (appeared ? share.share : 1 / Double(shares.count))))
                    }
                }
            }
            .frame(height: highlighted ? 7 : 5)
            HStack(spacing: 8) {
                ForEach(Array(shares.prefix(3).enumerated()), id: \.offset) { index, share in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(ModelShareStyle.color(index))
                            .frame(width: 5, height: 5)
                        Text("\(share.name) \(Int((share.share * 100).rounded()))%")
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(highlighted ? .white : .secondary)
                    }
                }
            }
            .lineLimit(1)
        }
        .animation(.spring(response: 0.8, dampingFraction: 0.85), value: appeared)
        .animation(Anim.subtle, value: highlighted)
        .onAppear { appeared = true }
    }
}
