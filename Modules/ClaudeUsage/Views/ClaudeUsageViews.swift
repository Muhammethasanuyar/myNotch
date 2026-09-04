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

/// A limit as a ring with the percentage inside.
struct UsageRing: View {
    let window: UsageWindow?
    let thresholds: UsageThresholds
    var diameter: CGFloat = 56
    var lineWidth: CGFloat = 6
    var dimmed = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: lineWidth)
            if let window {
                Circle()
                    .trim(from: 0, to: max(0.005, window.utilization))
                    .stroke(
                        ClaudeStyle.ringColor(level: ClaudeUsageRules.level(for: window.utilization, thresholds: thresholds)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.6), value: window.utilization)
                VStack(spacing: -1) {
                    Text("\(Int((window.utilization * 100).rounded()))%")
                        .font(.system(size: diameter * 0.26, weight: .semibold, design: .rounded).monospacedDigit())
                    Text("used")
                        .font(.system(size: diameter * 0.13))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("—")
                    .font(.system(size: diameter * 0.3, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
        .opacity(dimmed ? 0.5 : 1)
    }
}

/// The module's full interface: the two official limits as rings, and beside them what today
/// cost, which models did the work and how fast the current block is burning. Every number
/// carries its label and a tooltip: a status screen should not need decoding.
struct ClaudeDashboardView: View {
    let service: ClaudeUsageService
    let namespace: Namespace.ID

    /// Width of the label column in the details ("Today", "Models", "Burn").
    private static let labelWidth: CGFloat = 38

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            rings
            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(width: 1)
                .padding(.vertical, 4)
            details
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Rings

    private var rings: some View {
        HStack(alignment: .top, spacing: 10) {
            ring(kind: .fiveHour)
            ring(kind: .sevenDay)
        }
    }

    private func ring(kind: UsageWindowKind) -> some View {
        let window = service.snapshot?[kind]
        let remaining = window?.remaining(at: Date()).map(ClaudeUsageRules.formatRemaining)
        return VStack(spacing: 4) {
            UsageRing(window: window, thresholds: service.thresholds, dimmed: service.isStale)
            Text("\(kind.title) limit")
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
            Text(resetLabel(window: window, remaining: remaining))
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(width: 74)
        .help(ringHelp(kind: kind, window: window, remaining: remaining))
    }

    private func resetLabel(window: UsageWindow?, remaining: String?) -> String {
        if let remaining { return "resets in\n\(remaining)" }
        return window == nil ? "no data\nyet" : " "
    }

    private func ringHelp(kind: UsageWindowKind, window: UsageWindow?, remaining: String?) -> String {
        guard let window else { return "Anthropic has not reported this limit yet" }
        let used = Int((window.utilization * 100).rounded())
        let reset = remaining.map { "; it resets in \($0)" } ?? ""
        return "\(used)% of your \(kind.title.lowercased()) allowance is used\(reset)"
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            todayLine
            modelsLine
            burnLine
            Spacer(minLength: 0)
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "asterisk")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(service.isWorking ? ClaudeStyle.accent : .white.opacity(0.6))
                .symbolEffect(.pulse, options: .repeating, isActive: service.isWorking)
                .matchedGeometryEffect(id: ClaudeUsageModule.markID, in: namespace)
            // The title never wraps; whatever is short on room is the status beside it.
            Text("Claude Code")
                .font(.headline)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)
            Spacer(minLength: 4)
            Text(statusText)
                .font(.caption2)
                .foregroundStyle(service.isWorking ? ClaudeStyle.accent : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(service.isWorking ? "Claude Code is writing to a session log right now" : "The project Claude Code last worked in")
        }
    }

    private var statusText: String {
        let project = service.session?.customTitle ?? service.session?.projectName
        if service.isWorking { return project.map { "Working · \($0)" } ?? "Working…" }
        if let project { return "Idle · \(project)" }
        return service.hasLogs ? "Idle" : "No sessions yet"
    }

    /// "Today  9.5M tokens · $62.89": a label, the number, and a detail — or why there is none.
    private func statLine(_ label: String, value: String, detail: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: Self.labelWidth, alignment: .leading)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
            if let detail {
                Text("· \(detail)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private var todayLine: some View {
        switch service.costState {
        case .ready:
            if let today = service.cost?.today {
                statLine("Today", value: "\(ClaudeUsageRules.formatTokens(today.totalTokens)) tokens", detail: costDetail(for: today))
                    .help(costHelp(for: today))
            } else if service.cost != nil {
                statLine("Today", value: "nothing yet")
            } else {
                statLine("Today", value: "reading…")
            }
        case .notInstalled:
            statLine("Today", value: "needs ccusage", detail: "brew install ccusage")
                .help("Token counts and cost come from the ccusage tool; install it and the numbers appear")
        case .failed:
            statLine("Today", value: "ccusage failed", detail: "see log")
        case .unknown:
            EmptyView()
        }
    }

    /// ccusage prices from an offline table; a model it does not know comes out as $0, which is
    /// not the same as free, so the line says which one.
    private func costDetail(for today: CCUsageDay) -> String {
        if today.totalCost > 0 { return ClaudeUsageRules.formatCost(today.totalCost) }
        // Short, because the line is narrow; the tooltip names the model.
        let unpriced = today.modelBreakdowns.contains { $0.cost == 0 && ($0.outputTokens > 0 || $0.inputTokens > 0) }
        return unpriced ? "no price" : "$0.00"
    }

    private func costHelp(for today: CCUsageDay) -> String {
        let unpriced = today.modelBreakdowns.filter { $0.cost == 0 }.map { CCUsageParser.prettyModelName($0.modelName) }
        var help = "Tokens and spend today, from ccusage (offline price table)."
        if !unpriced.isEmpty {
            help += " No price is known for \(unpriced.joined(separator: ", ")), so those tokens count as $0."
        }
        return help
    }

    @ViewBuilder
    private var modelsLine: some View {
        if let today = service.cost?.today {
            let shares = ModelShare.compute(today.modelBreakdowns)
            if shares.count > 1 {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("Models")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: Self.labelWidth, alignment: .leading)
                        ModelShareLegend(shares: shares)
                    }
                    ModelShareBar(shares: shares)
                        .padding(.leading, Self.labelWidth + 5)
                }
                .help(today.totalCost > 0
                      ? "How today's spend splits across models"
                      : "How today's output tokens split across models (no prices to split)")
            } else if let only = shares.first {
                statLine("Model", value: only.name, detail: "all of today's work")
            }
        }
    }

    @ViewBuilder
    private var burnLine: some View {
        if let block = service.cost?.activeBlock, let rate = block.burnRate,
           let burn = ClaudeUsageRules.burnDescription(
               tokensPerMinute: rate.tokensPerMinuteForIndicator ?? rate.tokensPerMinute,
               costPerHour: rate.costPerHour,
               projectedCost: block.projection?.totalCost
           ) {
            statLine("Burn", value: burn.value, detail: burn.detail)
                .help("Pace of the current 5-hour block: input and output tokens per minute, spend per hour, and the spend expected by the time the block resets")
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: footerSymbol)
                .font(.system(size: 9))
            Text(footerText)
                .lineLimit(1)
                .help(service.auth == .ok ? "The official 5-hour and weekly limits, read from Anthropic every five minutes" : footerText)
            Spacer(minLength: 4)
            if let plan = service.subscriptionType, !plan.isEmpty {
                Text(plan.capitalized)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.white.opacity(0.14), in: Capsule())
                    .help("Your Claude plan, as recorded in Claude Code's sign-in")
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(service.auth == .ok ? .secondary : ClaudeStyle.warning)
    }

    private var footerSymbol: String {
        switch service.auth {
        case .ok: return service.isStale ? "clock" : "checkmark.circle"
        case .signedOut, .tokenExpired, .reauthRequired: return "person.crop.circle.badge.exclamationmark"
        case .rateLimited: return "hourglass"
        case .unreachable: return "wifi.exclamationmark"
        }
    }

    private var footerText: String {
        switch service.auth {
        case .ok:
            guard let fetched = service.snapshot?.fetchedAt else { return "Waiting for Anthropic's first reading" }
            return "Limits updated \(ClaudeUsageRules.formatRemaining(Date().timeIntervalSince(fetched))) ago"
        case .signedOut:
            return "Sign in with `claude` in Terminal to see limits"
        case .tokenExpired:
            return "Token expired — run `claude` once to refresh it"
        case .reauthRequired:
            return "Run `claude /login` — the token lacks a new scope"
        case .rateLimited(let until):
            return "Rate limited · retry at \(until.formatted(date: .omitted, time: .shortened))"
        case .unreachable:
            return service.snapshot == nil ? "Anthropic unreachable" : "Anthropic unreachable · showing last reading"
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

/// "● Opus 5 74%  ● Fable 5.1 26%"
private struct ModelShareLegend: View {
    let shares: [ModelShare]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(shares.prefix(3).enumerated()), id: \.offset) { index, share in
                HStack(spacing: 3) {
                    Circle()
                        .fill(ModelShareStyle.color(index))
                        .frame(width: 6, height: 6)
                    Text("\(share.name) \(Int((share.share * 100).rounded()))%")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .lineLimit(1)
    }
}

/// One thin bar split into segments, one colour per model. Drawn only for two or more models — a
/// single segment would just look like a meter stuck at full.
private struct ModelShareBar: View {
    let shares: [ModelShare]

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(Array(shares.enumerated()), id: \.offset) { index, share in
                    Capsule()
                        .fill(ModelShareStyle.color(index))
                        .frame(width: max(3, (proxy.size.width - 2 * CGFloat(shares.count - 1)) * share.share))
                }
            }
        }
        .frame(height: 4)
    }
}
