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
                Text("\(Int((window.utilization * 100).rounded()))%")
                    .font(.system(size: diameter * 0.26, weight: .semibold, design: .rounded).monospacedDigit())
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

/// The module's full interface: the two official limits, today's cost and the active block.
struct ClaudeDashboardView: View {
    let service: ClaudeUsageService
    let namespace: Namespace.ID

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
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
        HStack(alignment: .top, spacing: 12) {
            ring(kind: .fiveHour)
            ring(kind: .sevenDay)
        }
    }

    private func ring(kind: UsageWindowKind) -> some View {
        let window = service.snapshot?[kind]
        return VStack(spacing: 5) {
            UsageRing(window: window, thresholds: service.thresholds, dimmed: service.isStale)
            Text(kind.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                if window?.resetsAt != nil {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 8, weight: .semibold))
                }
                Text(resetLabel(for: window))
                    .font(.system(size: 9).monospacedDigit())
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .help("Time until this window resets")
        }
        .frame(width: 72)
    }

    private func resetLabel(for window: UsageWindow?) -> String {
        guard let remaining = window?.remaining(at: Date()) else { return " " }
        return ClaudeUsageRules.formatRemaining(remaining)
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            todayLine
            if let today = service.cost?.today, !today.modelBreakdowns.isEmpty {
                ModelSplitBar(breakdowns: today.modelBreakdowns)
            }
            blockLine
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
            Text("Claude Code")
                .font(.headline)
            if let plan = service.subscriptionType, !plan.isEmpty {
                Text(plan.capitalized)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.white.opacity(0.14), in: Capsule())
            }
            Spacer(minLength: 0)
            Text(statusText)
                .font(.caption2)
                .foregroundStyle(service.isWorking ? ClaudeStyle.accent : .secondary)
                .lineLimit(1)
        }
    }

    private var statusText: String {
        let project = service.session?.customTitle ?? service.session?.projectName
        if service.isWorking { return project.map { "Working · \($0)" } ?? "Working…" }
        if let project { return project }
        return service.hasLogs ? "Idle" : "No sessions yet"
    }

    @ViewBuilder
    private var todayLine: some View {
        switch service.costState {
        case .ready:
            if let today = service.cost?.today {
                Text("\(ClaudeUsageRules.formatCost(today.totalCost)) today · \(ClaudeUsageRules.formatTokens(today.totalTokens)) tokens")
                    .font(.subheadline.monospacedDigit())
            } else if service.cost != nil {
                Text("Nothing spent today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Reading cost…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .notInstalled:
            Text("Cost needs ccusage · brew install ccusage")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed:
            Text("ccusage failed · see log")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .unknown:
            EmptyView()
        }
    }

    @ViewBuilder
    private var blockLine: some View {
        if let block = service.cost?.activeBlock {
            HStack(spacing: 4) {
                Text("Block \(block.startTime.formatted(date: .omitted, time: .shortened))–\(block.endTime.formatted(date: .omitted, time: .shortened))")
                if let rate = block.burnRate?.costPerHour, rate > 0 {
                    Text("· \(ClaudeUsageRules.formatCost(rate))/h")
                }
                if let projected = block.projection?.totalCost, projected > 0 {
                    Text("· ≈\(ClaudeUsageRules.formatCost(projected)) by end")
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: footerSymbol)
                .font(.system(size: 9))
            Text(footerText)
                .lineLimit(1)
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
            guard let fetched = service.snapshot?.fetchedAt else { return "Waiting for the first reading" }
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

/// Share of today's cost per model family, as one thin bar with a legend.
struct ModelSplitBar: View {
    let breakdowns: [CCUsageDay.ModelBreakdown]

    private var segments: [(name: String, share: Double)] {
        let byFamily = Dictionary(grouping: breakdowns, by: { CCUsageParser.modelFamily($0.modelName) })
        let costs = byFamily.mapValues { $0.reduce(0) { $0 + $1.cost } }
        let useTokens = costs.values.reduce(0, +) <= 0
        let weights = useTokens
            ? byFamily.mapValues { Double($0.reduce(0) { $0 + $1.outputTokens }) }
            : costs
        let total = weights.values.reduce(0, +)
        guard total > 0 else { return [] }
        return weights.sorted { $0.value > $1.value }.map { ($0.key, $0.value / total) }
    }

    var body: some View {
        let parts = segments
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                        Capsule()
                            .fill(ClaudeStyle.accent.opacity(1 - Double(index) * 0.35))
                            .frame(width: max(3, proxy.size.width * part.share - 2))
                    }
                }
            }
            .frame(height: 4)
            Text(parts.map { "\($0.name) \(Int(($0.share * 100).rounded()))%" }.joined(separator: " · "))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
