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
    /// Short text under the percentage: "5h", "7d", or a model's name for a scoped limit.
    let badge: String
    /// How long the window is, for the thin "time passed" arc.
    let windowKind: UsageWindowKind
    let thresholds: UsageThresholds
    let now: Date
    var isWorking = false
    var diameter: CGFloat = 54
    var dimmed = false

    @State private var appeared = false
    @State private var glowing = false

    private var usage: Double { appeared ? (window?.utilization ?? 0) : 0 }
    private var elapsed: Double { appeared ? (window?.elapsedFraction(kind: windowKind, at: now) ?? 0) : 0 }
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
                Text(window.map { ClaudeUsageRules.percent(Int(($0.utilization * 100).rounded())) } ?? "—")
                    .font(.system(size: diameter * 0.23, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text(badge)
                    .font(.system(size: diameter * 0.13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: diameter - 18)
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
    /// A limit ring, by `UsageSubject.id`.
    case ring(String)
    /// The blocks row's title.
    case blocks
    /// One block card, by the block's id.
    case block(String)
    case spend
    case tokens
    case pace
    case models
    case status
    case plan
    case working
}

/// The module's full interface, built to be read as shapes: two rings for the limits with the
/// day's 5-hour blocks charted beneath them, icon chips for today's numbers, a bar for where the
/// tokens went, one for the models, a status dot. Everything moves — arcs sweep in, bars grow,
/// digits roll, the mark pulses — and everything explains itself: rest the cursor on any indicator
/// and it lifts towards you while a sentence appears in the card.
struct ClaudeDashboardView: View {
    let service: ClaudeUsageService
    let namespace: Namespace.ID

    @State private var focus: DashboardFocus?
    @State private var appeared = false

    var body: some View {
        // Every half minute, so the thin "time passed" arcs and countdowns keep moving while open.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(alignment: .top, spacing: 14) {
                leftColumn(at: context.date)
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

    // MARK: Rings and blocks

    /// The account's two windows first, then every limit scoped to a model (Fable's weekly, say).
    private var ringSubjects: [(subject: UsageSubject, window: UsageWindow?)] {
        var list: [(UsageSubject, UsageWindow?)] = [
            (.window(.fiveHour), service.snapshot?.fiveHour),
            (.window(.sevenDay), service.snapshot?.sevenDay)
        ]
        for limit in service.snapshot?.scopedLimits ?? [] {
            list.append((.scoped(name: limit.name, windowKind: limit.windowKind), limit.window))
        }
        return list
    }

    private func leftColumn(at now: Date) -> some View {
        let subjects = ringSubjects
        let width = max(144, CGFloat(subjects.count) * 54 + CGFloat(subjects.count - 1) * 10)
        return VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(subjects, id: \.subject.id) { entry in
                    ring(entry.subject, window: entry.window, at: now)
                }
            }
            .reveal(appeared, index: 0)
            BlocksRow(
                blocks: service.cost?.todayBlocks ?? [],
                activeID: service.cost?.activeBlock?.id,
                now: now,
                isWorking: service.isWorking,
                focus: $focus
            )
            .frame(maxWidth: .infinity)
            .reveal(appeared, index: 2)
        }
        .frame(width: width)
    }

    private func ring(_ subject: UsageSubject, window: UsageWindow?, at now: Date) -> some View {
        let remaining = window?.remaining(at: now).map { ClaudeUsageRules.formatRemaining($0) }
        let badge: String
        switch subject {
        case .window(let kind): badge = kind.badge()
        case .scoped(let name, _): badge = name
        }
        return VStack(spacing: 4) {
            UsageRing(
                window: window,
                badge: badge,
                windowKind: subject.windowKind,
                thresholds: service.thresholds,
                now: now,
                isWorking: subject == .window(.fiveHour) && service.isWorking,
                dimmed: service.isStale
            )
            // Natural width, centred under the ring: "20s 57dk" may lean into the gutter rather than wrap.
            HStack(spacing: 3) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 8, weight: .semibold))
                    .symbolEffect(.bounce, value: remaining)
                Text(remaining ?? "—")
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .contentTransition(.numericText())
            }
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(.secondary)
        }
        .frame(width: 54)
        .spotlight(.ring(subject.id), focus: $focus)
    }

    // MARK: Details

    private func details(at now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header
                .reveal(appeared, index: 1)
            statChips
                .reveal(appeared, index: 2)
            compositionRow
                .reveal(appeared, index: 3)
            modelsRow
                .reveal(appeared, index: 4)
            Spacer(minLength: 0)
            footer
                .reveal(appeared, index: 5)
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
                    statChip(.spend, "dollarsign.circle", value: costValue(for: today),
                             caption: String(localized: "caption.spend", defaultValue: "spend"), bounce: today.totalCost)
                    statChip(.tokens, "number", value: ClaudeUsageRules.formatTokens(today.totalTokens),
                             caption: String(localized: "caption.tokens", defaultValue: "tokens"), bounce: Double(today.totalTokens))
                } else {
                    statChip(.spend, "dollarsign.circle", value: "0", caption: String(localized: "caption.spend", defaultValue: "spend"), bounce: 0)
                }
                if let block = service.cost?.activeBlock, let rate = block.burnRate,
                   let perMinute = rate.tokensPerMinuteForIndicator ?? rate.tokensPerMinute, perMinute > 0 {
                    statChip(.pace, "flame.fill",
                             value: ClaudeUsageRules.formatTokens(Int(perMinute.rounded())) + "/" + String(localized: "unit.minute", defaultValue: "min"),
                             caption: String(localized: "caption.pace", defaultValue: "pace"),
                             bounce: perMinute, flicker: service.isWorking)
                }
            case .notInstalled:
                statChip(.spend, "arrow.down.circle", value: "ccusage", caption: String(localized: "caption.install", defaultValue: "install"), bounce: 0)
            case .failed:
                statChip(.spend, "exclamationmark.circle", value: "ccusage", caption: String(localized: "caption.failed", defaultValue: "failed"), bounce: 0)
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

    /// Where today's tokens went: answers, prompts, cache.
    @ViewBuilder
    private var compositionRow: some View {
        if let today = service.cost?.today {
            let parts = TokenPart.compose(today)
            if !parts.isEmpty {
                TokenCompositionBar(parts: parts, highlighted: focus == .tokens)
                    .spotlight(.tokens, focus: $focus)
            }
        }
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
        case .signedOut: return String(localized: "action.signIn", defaultValue: "Sign in with `claude`")
        case .tokenExpired: return String(localized: "action.refreshToken", defaultValue: "Run `claude` to refresh the token")
        case .reauthRequired: return String(localized: "action.login", defaultValue: "Run `claude /login`")
        }
    }

    // MARK: Explanations

    private func explanation(for focus: DashboardFocus, at now: Date) -> String {
        switch focus {
        case .ring(let id):
            guard let entry = ringSubjects.first(where: { $0.subject.id == id }) else { return "" }
            return ClaudeUsageRules.ringExplanation(
                title: ClaudeUsageRules.subjectTitle(entry.subject),
                windowKind: entry.subject.windowKind,
                window: entry.window,
                now: now
            )
        case .blocks:
            return ClaudeUsageRules.blocksExplanation(blocks: service.cost?.todayBlocks ?? [], activeID: service.cost?.activeBlock?.id)
        case .block(let id):
            guard let block = service.cost?.todayBlocks.first(where: { $0.id == id }) else { return "" }
            return ClaudeUsageRules.blockExplanation(block, isActive: block.id == service.cost?.activeBlock?.id, now: now)
        case .spend:
            switch service.costState {
            case .notInstalled:
                return String(localized: "explain.ccusage.missing", defaultValue: "Spend and tokens come from the ccusage tool. Install it with `brew install ccusage` (or `npm i -g ccusage`).")
            case .failed:
                return String(localized: "explain.ccusage.failed", defaultValue: "ccusage could not produce a report; the log (subsystem com.emre.mynotch) has the error.")
            default:
                return service.cost?.today.map { ClaudeUsageRules.spendExplanation(day: $0) }
                    ?? String(localized: "explain.spend.nothing", defaultValue: "Nothing has been spent today.")
            }
        case .tokens:
            return service.cost?.today.map { ClaudeUsageRules.tokensExplanation(day: $0) }
                ?? String(localized: "explain.tokens.nothing", defaultValue: "No tokens used today.")
        case .pace:
            guard let block = service.cost?.activeBlock else {
                return String(localized: "explain.pace.noBlock", defaultValue: "No 5-hour block is active.")
            }
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
            let plan = service.subscriptionType?.capitalized ?? String(localized: "explain.plan.unknown", defaultValue: "unknown")
            return String(localized: "explain.plan", defaultValue: "Your Claude plan (\(plan)), as recorded in Claude Code's sign-in on this Mac.")
        case .working:
            if service.isWorking {
                let project = (service.session?.customTitle ?? service.session?.projectName).map {
                    String(localized: "explain.working.inProject", defaultValue: " in \($0)")
                } ?? ""
                return String(localized: "explain.working.active", defaultValue: "Claude Code is writing to a session log right now\(project).")
            }
            return service.hasLogs
                ? String(localized: "explain.working.quiet", defaultValue: "Claude Code is quiet. It counts as working while a session log changed within the last ten seconds.")
                : String(localized: "explain.working.noLogs", defaultValue: "No Claude Code session logs were found on this Mac yet.")
        }
    }

    private func statusExplanation(at now: Date) -> String {
        switch service.auth {
        case .ok:
            guard let fetched = service.snapshot?.fetchedAt else {
                return String(localized: "explain.status.waiting", defaultValue: "Waiting for Anthropic's first reading of your limits.")
            }
            let age = ClaudeUsageRules.formatRemaining(now.timeIntervalSince(fetched))
            let stale = service.isStale ? String(localized: "explain.status.stale", defaultValue: " This reading is older than fifteen minutes.") : ""
            return String(localized: "explain.status.fresh", defaultValue: "Limits read from Anthropic \(age) ago; they refresh every five minutes.\(stale)")
        case .signedOut:
            return String(localized: "explain.status.signedOut", defaultValue: "No Claude Code sign-in was found on this Mac. Run `claude` in Terminal once and the limits appear.")
        case .tokenExpired:
            return String(localized: "explain.status.tokenExpired", defaultValue: "The access token has expired. Running `claude` refreshes it; nothing is written by MyNotch.")
        case .reauthRequired:
            return String(localized: "explain.status.reauth", defaultValue: "The token lacks a scope the usage endpoint now needs; only `claude /login` can grant it.")
        case .rateLimited(let until):
            return String(localized: "explain.status.rateLimited", defaultValue: "Anthropic rate-limited the usage endpoint. The next attempt is at \(until.formatted(date: .omitted, time: .shortened)).")
        case .unreachable:
            return service.snapshot == nil
                ? String(localized: "explain.status.unreachable", defaultValue: "Anthropic could not be reached.")
                : String(localized: "explain.status.unreachableStale", defaultValue: "Anthropic could not be reached; the last reading is shown.")
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

// MARK: - Charts

/// Today's 5-hour blocks as a row of cards, oldest first: each card names the hour the block
/// began and how many tokens it used; the block that is still running is drawn in the accent with
/// a thin line along its foot showing how much of its five hours have passed. No time axis — the
/// question a glance asks is "which sessions did I have today and how big were they", and a
/// block that crosses midnight or has only just begun reads the same as any other.
private struct BlocksRow: View {
    let blocks: [CCUsageBlock]
    let activeID: String?
    let now: Date
    var isWorking = false
    @Binding var focus: DashboardFocus?

    @State private var appeared = false

    private static let cardHeight: CGFloat = 29
    private static let maxCardWidth: CGFloat = 72

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(String(localized: "chart.blocks", defaultValue: "today's 5-hour blocks"))
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Color.white.opacity(focus == .blocks ? 0.9 : 0.45))
                .lineLimit(1)
                .spotlight(.blocks, focus: $focus)
            HStack(spacing: 4) {
                if blocks.isEmpty {
                    Text(String(localized: "chart.blocks.none", defaultValue: "none yet"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.4))
                        .frame(height: Self.cardHeight)
                        .padding(.horizontal, 8)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                        card(block, index: index)
                    }
                }
            }
        }
        .onAppear { appeared = true }
    }

    private func card(_ block: CCUsageBlock, index: Int) -> some View {
        let active = block.id == activeID
        let focused = focus == .block(block.id)
        let elapsed = min(1, max(0, now.timeIntervalSince(block.startTime) / max(1, block.endTime.timeIntervalSince(block.startTime))))
        let background: Color = active ? ClaudeStyle.accent : Color.white.opacity(focused ? 0.18 : 0.1)
        let primary: Color = active ? Color.black.opacity(0.85) : Color.white.opacity(0.92)
        let secondary: Color = active ? Color.black.opacity(0.6) : Color.white.opacity(0.5)
        return VStack(spacing: 1) {
            // `.minute()` alone is not zero-padded in every locale ("22:0" in tr_TR).
            Text(block.startTime.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                .font(.system(size: 8, weight: .medium).monospacedDigit())
                .foregroundStyle(secondary)
            Text(ClaudeUsageRules.formatTokens(block.totalTokens))
                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(primary)
                .contentTransition(.numericText())
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        // Room at the foot for the running block's progress line.
        .padding(.bottom, active ? 4 : 0)
        .frame(maxWidth: Self.maxCardWidth)
        .frame(maxWidth: .infinity)
        .frame(height: Self.cardHeight)
        .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(alignment: .bottom) {
            if active {
                // How far into its five hours the running block is.
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.25))
                        Capsule().fill(Color.white.opacity(0.9)).frame(width: proxy.size.width * CGFloat(appeared ? elapsed : 0))
                    }
                }
                .frame(height: 2)
                .padding(.horizontal, 6)
                .padding(.bottom, 3)
                .animation(.easeOut(duration: 0.8), value: elapsed)
            }
        }
        .shadow(color: ClaudeStyle.accent.opacity(active && isWorking ? 0.55 : 0), radius: 5)
        .scaleEffect(appeared ? 1 : 0.8)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.06), value: appeared)
        .spotlight(.block(block.id), focus: $focus)
    }
}

/// Where the tokens went, as one thin bar: answers, prompts, cache. Cache usually dwarfs the rest,
/// which is the point — it is the cheap part.
private struct TokenCompositionBar: View {
    let parts: [TokenPart]
    var highlighted = false

    @State private var appeared = false

    private static func color(_ kind: TokenPart.Kind) -> Color {
        switch kind {
        case .output: return ClaudeStyle.accent
        case .input: return .white.opacity(0.6)
        case .cache: return .white.opacity(0.28)
        }
    }

    private static func label(_ kind: TokenPart.Kind) -> String {
        switch kind {
        case .output: return String(localized: "legend.output", defaultValue: "out")
        case .input: return String(localized: "legend.input", defaultValue: "in")
        case .cache: return String(localized: "legend.cache", defaultValue: "cache")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                        Capsule()
                            .fill(Self.color(part.kind))
                            .frame(width: max(3, (proxy.size.width - 2 * CGFloat(parts.count - 1)) * (appeared ? part.share : 1 / Double(parts.count))))
                    }
                }
            }
            .frame(height: highlighted ? 7 : 5)
            HStack(spacing: 8) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Self.color(part.kind))
                            .frame(width: 5, height: 5)
                        Text("\(Self.label(part.kind)) \(ClaudeUsageRules.formatTokens(part.tokens))")
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(highlighted ? .white : .secondary)
                            .contentTransition(.numericText())
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
                        Text("\(share.name) \(ClaudeUsageRules.percent(Int((share.share * 100).rounded())))")
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
