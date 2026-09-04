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
/// the card opens and glide when the numbers change.
struct UsageRing: View {
    let window: UsageWindow?
    let kind: UsageWindowKind
    let thresholds: UsageThresholds
    let now: Date
    var diameter: CGFloat = 62
    var dimmed = false

    @State private var appeared = false

    private var usage: Double { appeared ? (window?.utilization ?? 0) : 0 }
    private var elapsed: Double { appeared ? (window?.elapsedFraction(kind: kind, at: now) ?? 0) : 0 }

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
            if let window {
                Circle()
                    .trim(from: 0, to: max(0.004, usage))
                    .stroke(
                        ClaudeStyle.ringColor(level: ClaudeUsageRules.level(for: window.utilization, thresholds: thresholds)),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(7)
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
        .onAppear { appeared = true }
    }
}

/// The module's full interface, built to be read as shapes rather than sentences: two rings for
/// the limits, a row of icon chips for today's numbers, a split bar for the models, a status dot.
/// Words are kept for what only words can say, and the rest lives in tooltips.
struct ClaudeDashboardView: View {
    let service: ClaudeUsageService
    let namespace: Namespace.ID

    var body: some View {
        // Once a minute, so the thin "time passed" arcs keep moving while the card is open.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(alignment: .top, spacing: 14) {
                rings(at: context.date)
                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 1)
                    .padding(.vertical, 6)
                details
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            UsageRing(window: window, kind: kind, thresholds: service.thresholds, now: now, dimmed: service.isStale)
            HStack(spacing: 3) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 8, weight: .semibold))
                Text(remaining ?? "—")
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .contentTransition(.numericText())
            }
            .foregroundStyle(.secondary)
        }
        .frame(width: 66)
        .help(ringHelp(kind: kind, window: window, remaining: remaining))
    }

    private func ringHelp(kind: UsageWindowKind, window: UsageWindow?, remaining: String?) -> String {
        guard let window else { return "Anthropic has not reported the \(kind.title.lowercased()) limit yet" }
        let used = Int((window.utilization * 100).rounded())
        let reset = remaining.map { "; the window resets in \($0)" } ?? ""
        return "\(kind.title) limit: \(used)% used\(reset). The thin outer arc is how much of the window has passed."
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            statChips
            modelsRow
            Spacer(minLength: 0)
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            if service.isWorking {
                // Working: the project it is in, and a ripple that only runs while it does.
                HStack(spacing: 4) {
                    if let project = service.session?.customTitle ?? service.session?.projectName {
                        Text(project)
                            .font(.caption2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .bold))
                        .symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: true)
                }
                .foregroundStyle(ClaudeStyle.accent)
                .transition(.opacity)
                .help("Claude Code is writing to a session log right now")
            }
        }
        .animation(Anim.subtle, value: service.isWorking)
    }

    /// Today's numbers as icon chips: spend, tokens, and the pace of the current block.
    @ViewBuilder
    private var statChips: some View {
        HStack(spacing: 6) {
            switch service.costState {
            case .ready:
                if let today = service.cost?.today {
                    statChip("dollarsign.circle", value: costValue(for: today), help: costHelp(for: today))
                    statChip("number", value: ClaudeUsageRules.formatTokens(today.totalTokens), help: "Tokens used today, in and out, cache included")
                } else {
                    statChip("dollarsign.circle", value: "0", help: "Nothing spent today yet")
                }
                if let block = service.cost?.activeBlock, let rate = block.burnRate,
                   let burn = ClaudeUsageRules.burnDescription(
                       tokensPerMinute: rate.tokensPerMinuteForIndicator ?? rate.tokensPerMinute,
                       costPerHour: rate.costPerHour,
                       projectedCost: block.projection?.totalCost
                   ) {
                    statChip("flame", value: burn.value.replacingOccurrences(of: " tok/min", with: "/min"),
                             help: "Pace of the current 5-hour block: \(burn.value)" + (burn.detail.map { ", \($0)" } ?? ""))
                }
            case .notInstalled:
                statChip("arrow.down.circle", value: "ccusage", help: "Spend and tokens come from the ccusage tool — install it with `brew install ccusage`")
            case .failed:
                statChip("exclamationmark.circle", value: "ccusage", help: "ccusage failed; see the log")
            case .unknown:
                EmptyView()
            }
        }
    }

    private func statChip(_ symbol: String, value: String, help: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(.white.opacity(0.09), in: Capsule())
        .lineLimit(1)
        .help(help)
    }

    /// ccusage prices from an offline table; a model it does not know comes out as $0, which is
    /// not free, so that shows as a dash and the tooltip names the model.
    private func costValue(for today: CCUsageDay) -> String {
        if today.totalCost > 0 { return ClaudeUsageRules.formatCost(today.totalCost).replacingOccurrences(of: "$", with: "") }
        let unpriced = today.modelBreakdowns.contains { $0.cost == 0 && ($0.outputTokens > 0 || $0.inputTokens > 0) }
        return unpriced ? "—" : "0"
    }

    private func costHelp(for today: CCUsageDay) -> String {
        let unpriced = today.modelBreakdowns.filter { $0.cost == 0 }.map { CCUsageParser.prettyModelName($0.modelName) }
        var help = today.totalCost > 0 ? "Spent today: \(ClaudeUsageRules.formatCost(today.totalCost))." : "Spent today, as far as ccusage can tell."
        if !unpriced.isEmpty {
            help += " No price is known for \(unpriced.joined(separator: ", ")), so those tokens count as $0."
        }
        return help
    }

    /// Which models did today's work: one chip for one model, a segmented bar for several.
    @ViewBuilder
    private var modelsRow: some View {
        if let today = service.cost?.today {
            let shares = ModelShare.compute(today.modelBreakdowns)
            if shares.count > 1 {
                ModelShareBar(shares: shares)
                    .help(today.totalCost > 0
                          ? "How today's spend splits across models"
                          : "How today's output tokens split across models (no prices to split)")
            } else if let only = shares.first {
                HStack(spacing: 4) {
                    Circle()
                        .fill(ClaudeStyle.accent)
                        .frame(width: 6, height: 6)
                    Text(only.name)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .help("Every token today went through \(only.name)")
            }
        }
    }

    /// A dot says whether the numbers are fresh; words appear only when something needs doing.
    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .shadow(color: statusColor.opacity(0.6), radius: 3)
            if let action = actionText {
                Text(action)
                    .font(.system(size: 10))
                    .foregroundStyle(ClaudeStyle.warning)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let plan = service.subscriptionType, !plan.isEmpty {
                Text(plan.capitalized)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.white.opacity(0.12), in: Capsule())
                    .help("Your Claude plan, as recorded in Claude Code's sign-in")
            }
        }
        .help(statusHelp)
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

    private var statusHelp: String {
        switch service.auth {
        case .ok:
            guard let fetched = service.snapshot?.fetchedAt else { return "Waiting for Anthropic's first reading" }
            return "Limits read from Anthropic \(ClaudeUsageRules.formatRemaining(Date().timeIntervalSince(fetched))) ago" + (service.isStale ? " — older than 15 minutes" : "")
        case .signedOut: return "No Claude Code sign-in found on this Mac; run `claude` in Terminal once"
        case .tokenExpired: return "The access token has expired; running `claude` refreshes it"
        case .reauthRequired: return "The token lacks a scope the usage endpoint now needs; only `claude /login` fixes that"
        case .rateLimited(let until): return "Anthropic rate-limited the usage endpoint; retrying at \(until.formatted(date: .omitted, time: .shortened))"
        case .unreachable: return service.snapshot == nil ? "Anthropic could not be reached" : "Anthropic could not be reached; showing the last reading"
        }
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
/// or more models — a single segment would just look like a meter stuck at full.
private struct ModelShareBar: View {
    let shares: [ModelShare]

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
            .frame(height: 5)
            HStack(spacing: 8) {
                ForEach(Array(shares.prefix(3).enumerated()), id: \.offset) { index, share in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(ModelShareStyle.color(index))
                            .frame(width: 5, height: 5)
                        Text("\(share.name) \(Int((share.share * 100).rounded()))%")
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .lineLimit(1)
        }
        .animation(.spring(response: 0.8, dampingFraction: 0.85), value: appeared)
        .onAppear { appeared = true }
    }
}
