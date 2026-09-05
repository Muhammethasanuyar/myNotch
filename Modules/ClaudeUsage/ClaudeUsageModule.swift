import SwiftUI

/// Claude Code in the notch: a pulsing mark while it works, the official 5-hour and weekly limits
/// as rings, today's cost from ccusage, and a popup when a limit threshold is crossed.
@MainActor
@Observable
final class ClaudeUsageModule: NotchModule {
    let id = "claude"
    let displayName = "Claude Code"
    /// Below media: music that is playing keeps the strip; Claude's alerts still interrupt as popups.
    let priority = 5

    var isEnabled = true
    private(set) var activity: ModuleActivity = .idle

    let service: ClaudeUsageService
    @ObservationIgnored private var context: ModuleContext?

    /// Claude Code is a CLI, so there is no app icon to borrow; the screen is offered wherever it
    /// has been used or has limits to report.
    var screens: [ModuleScreen] {
        [ModuleScreen(
            id: id,
            moduleID: id,
            title: displayName,
            symbolName: "asterisk",
            isAvailable: service.hasLogs || service.snapshot != nil
        )]
    }

    init(service: ClaudeUsageService = ClaudeUsageService()) {
        self.service = service
    }

    func start(context: ModuleContext) {
        self.context = context
        service.onWorkingChanged = { [weak self] _ in self?.updateActivity() }
        service.onDataChanged = { [weak self] in self?.updateActivity() }
        service.onCrossing = { [weak self] crossing in
            guard let self else { return }
            self.context?.post(ClaudeUsageRules.crossingEvent(crossing, moduleID: id, now: Date()))
        }
        service.onWindowReset = { [weak self] kind, _ in
            guard let self else { return }
            self.context?.post(ClaudeUsageRules.resetEvent(kind, moduleID: id))
        }
        service.start()
    }

    func stop() {
        service.stop()
        activity = .idle
        context?.activityChanged()
    }

    private func updateActivity() {
        let next = ClaudeUsageRules.activity(isWorking: service.isWorking, fiveHour: service.snapshot?.fiveHour, thresholds: service.thresholds)
        guard next != activity else { return }
        activity = next
        context?.activityChanged()
    }

    // MARK: Views

    func compactLeading(namespace: Namespace.ID) -> AnyView {
        AnyView(ClaudeCompactLeading(service: service, namespace: namespace))
    }

    func compactTrailing(namespace: Namespace.ID) -> AnyView {
        AnyView(ClaudeCompactTrailing(service: service))
    }

    func expandedView(namespace: Namespace.ID) -> AnyView {
        AnyView(ClaudeDashboardView(service: service, namespace: namespace))
    }

    static let markID = "claude.mark"
}

/// Pure decisions of the module, kept out of the view model so they can be tested. Every string a
/// user sees is looked up in the string catalog; `bundle` lets tests ask for the source language.
nonisolated enum ClaudeUsageRules {
    /// Live while Claude is working, and while the 5-hour window is past the warning threshold so
    /// the number stays in view when it matters.
    static func activity(isWorking: Bool, fiveHour: UsageWindow?, thresholds: UsageThresholds) -> ModuleActivity {
        if isWorking { return .live }
        if let fiveHour, fiveHour.utilization >= thresholds.warning { return .live }
        return .idle
    }

    /// "5-hour", "Weekly", or "Fable (weekly)".
    static func subjectTitle(_ subject: UsageSubject, bundle: Bundle = .main) -> String {
        switch subject {
        case .window(let kind):
            return kind.title(bundle: bundle)
        case .scoped(let name, let windowKind):
            return String(localized: "scoped.title", defaultValue: "\(name) (\(windowKind.title(bundle: bundle).lowercased()))", bundle: bundle)
        }
    }

    static func crossingEvent(_ crossing: ThresholdCrossing, moduleID: String, now: Date, bundle: Bundle = .main) -> NotchEvent {
        let percent = percent(Int((crossing.window.utilization * 100).rounded()), bundle: bundle)
        var detail = crossing.threshold >= 0.95
            ? String(localized: "event.crossing.nearlyExhausted", defaultValue: "Nearly exhausted", bundle: bundle)
            : String(localized: "event.crossing.slowDown", defaultValue: "Slow down", bundle: bundle)
        if let remaining = crossing.window.remaining(at: now) {
            detail += String(localized: "event.crossing.resetsIn", defaultValue: " — resets in \(formatRemaining(remaining, bundle: bundle))", bundle: bundle)
        }
        return NotchEvent(
            moduleID: moduleID,
            title: String(localized: "event.crossing.title", defaultValue: "\(subjectTitle(crossing.subject, bundle: bundle)) limit at \(percent)", bundle: bundle),
            detail: detail,
            symbolName: crossing.threshold >= 0.95 ? "exclamationmark.triangle.fill" : "gauge.with.needle",
            duration: 4
        )
    }

    static func resetEvent(_ kind: UsageWindowKind, moduleID: String, bundle: Bundle = .main) -> NotchEvent {
        NotchEvent(
            moduleID: moduleID,
            title: String(localized: "event.reset.title", defaultValue: "\(kind.title(bundle: bundle)) window reset", bundle: bundle),
            detail: String(localized: "event.reset.detail", defaultValue: "Fresh allowance", bundle: bundle),
            symbolName: "arrow.counterclockwise",
            duration: 3
        )
    }

    /// What the compact wing shows: the 5-hour percentage when known, else today's cost.
    static func compactLabel(fiveHour: UsageWindow?, todayCost: Double?, bundle: Bundle = .main) -> String? {
        if let fiveHour { return percent(Int((fiveHour.utilization * 100).rounded()), bundle: bundle) }
        if let todayCost { return formatCost(todayCost) }
        return nil
    }

    /// "26%" — or "%26" where the language puts the sign first.
    static func percent(_ value: Int, bundle: Bundle = .main) -> String {
        String(localized: "percent", defaultValue: "\(value)%", bundle: bundle)
    }

    /// "2d 3h", "1h 20m", "45m", "<1m".
    static func formatRemaining(_ interval: TimeInterval, bundle: Bundle = .main) -> String {
        let minutes = Int(interval / 60)
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        let rest = minutes % 60
        if days > 0 {
            return hours > 0
                ? String(localized: "time.daysHours", defaultValue: "\(days)d \(hours)h", bundle: bundle)
                : String(localized: "time.days", defaultValue: "\(days)d", bundle: bundle)
        }
        if hours > 0 {
            return rest > 0
                ? String(localized: "time.hoursMinutes", defaultValue: "\(hours)h \(rest)m", bundle: bundle)
                : String(localized: "time.hours", defaultValue: "\(hours)h", bundle: bundle)
        }
        return minutes > 0
            ? String(localized: "time.minutes", defaultValue: "\(minutes)m", bundle: bundle)
            : String(localized: "time.underMinute", defaultValue: "<1m", bundle: bundle)
    }

    /// "$0.03", "$4.20", "$127".
    static func formatCost(_ usd: Double) -> String {
        if usd >= 100 { return "$\(Int(usd.rounded()))" }
        return String(format: "$%.2f", usd)
    }

    /// "48K", "1.2M", "64.2M".
    static func formatTokens(_ count: Int) -> String {
        switch count {
        case ..<1_000: return "\(count)"
        case ..<1_000_000: return "\(count / 1_000)K"
        default: return String(format: "%.1fM", Double(count) / 1_000_000)
        }
    }

    /// The burn line: how fast the current block is going, and where that leads.
    /// - Returns: the headline ("3K tok/min") and, when the tool could price it, the money part.
    static func burnDescription(tokensPerMinute: Double?, costPerHour: Double?, projectedCost: Double?, bundle: Bundle = .main) -> (value: String, detail: String?)? {
        guard let tokensPerMinute, tokensPerMinute > 0 else { return nil }
        let value = String(localized: "burn.tokensPerMinute", defaultValue: "\(formatTokens(Int(tokensPerMinute.rounded()))) tok/min", bundle: bundle)
        guard let costPerHour, costPerHour > 0 else { return (value, nil) }
        var detail = String(localized: "burn.perHour", defaultValue: "\(formatCost(costPerHour))/h", bundle: bundle)
        if let projectedCost, projectedCost > 0 {
            detail += String(localized: "burn.projected", defaultValue: " · ≈\(formatCost(projectedCost)) by reset", bundle: bundle)
        }
        return (value, detail)
    }

    /// Ring colour by fill: calm, then warning, then critical.
    static func level(for utilization: Double, thresholds: UsageThresholds) -> Int {
        if utilization >= thresholds.critical { return 2 }
        if utilization >= thresholds.warning { return 1 }
        return 0
    }

    // MARK: Explanations shown while the cursor rests on an indicator

    static func ringExplanation(kind: UsageWindowKind, window: UsageWindow?, now: Date, bundle: Bundle = .main) -> String {
        ringExplanation(title: kind.title(bundle: bundle), windowKind: kind, window: window, now: now, bundle: bundle)
    }

    static func ringExplanation(title: String, windowKind kind: UsageWindowKind, window: UsageWindow?, now: Date, bundle: Bundle = .main) -> String {
        guard let window else {
            return String(localized: "explain.ring.noData", defaultValue: "\(title) limit — Anthropic has not reported it yet.", bundle: bundle)
        }
        let used = percent(Int((window.utilization * 100).rounded()), bundle: bundle)
        let resets = window.remaining(at: now).map {
            String(localized: "explain.ring.resetsIn", defaultValue: ", resets in \(formatRemaining($0, bundle: bundle))", bundle: bundle)
        } ?? ""
        if let elapsed = window.elapsedFraction(kind: kind, at: now) {
            let passed = percent(Int((elapsed * 100).rounded()), bundle: bundle)
            return String(localized: "explain.ring", defaultValue: "\(title) limit — \(used) of the allowance used\(resets). Outer arc: \(passed) of the window has passed.", bundle: bundle)
        }
        return String(localized: "explain.ring.noElapsed", defaultValue: "\(title) limit — \(used) of the allowance used\(resets).", bundle: bundle)
    }

    static func spendExplanation(day: CCUsageDay, bundle: Bundle = .main) -> String {
        let unpriced = day.modelBreakdowns.filter { $0.cost == 0 && ($0.outputTokens > 0 || $0.inputTokens > 0) }
            .map { CCUsageParser.prettyModelName($0.modelName) }
        var text = day.totalCost > 0
            ? String(localized: "explain.spend.priced", defaultValue: "Spent today: \(formatCost(day.totalCost)), priced by ccusage's offline table.", bundle: bundle)
            : String(localized: "explain.spend.unpricedBase", defaultValue: "Spend today, as far as ccusage can price it.", bundle: bundle)
        if !unpriced.isEmpty {
            text += String(localized: "explain.spend.unpriced", defaultValue: " No price is known for \(unpriced.joined(separator: ", ")) — its tokens count as $0.", bundle: bundle)
        }
        return text
    }

    /// Claude Code serves nearly the whole prompt from the cache, so "in" is only the uncached
    /// remainder and looks tiny next to the cache — the sentence says so, or the bar reads as wrong.
    static func tokensExplanation(day: CCUsageDay, bundle: Bundle = .main) -> String {
        String(
            localized: "explain.tokens",
            defaultValue: "Tokens today: \(formatTokens(day.totalTokens)) — \(formatTokens(day.inputTokens)) in (the part not served from cache), \(formatTokens(day.outputTokens)) out, \(formatTokens(day.cacheReadTokens + day.cacheCreationTokens)) cache (\(formatTokens(day.cacheReadTokens)) read + \(formatTokens(day.cacheCreationTokens)) written). Claude Code reads most of each prompt from the cache, which is why \"in\" looks small.",
            bundle: bundle
        )
    }

    static func paceExplanation(tokensPerMinute: Double?, costPerHour: Double?, projectedCost: Double?, blockEnd: Date, now: Date, bundle: Bundle = .main) -> String {
        guard let burn = burnDescription(tokensPerMinute: tokensPerMinute, costPerHour: costPerHour, projectedCost: projectedCost, bundle: bundle) else {
            return String(localized: "explain.pace.none", defaultValue: "Pace of the current 5-hour block.", bundle: bundle)
        }
        let detail = burn.detail.map { String(localized: "explain.pace.detail", defaultValue: ", \($0)", bundle: bundle) } ?? ""
        let ends = formatRemaining(max(0, blockEnd.timeIntervalSince(now)), bundle: bundle)
        return String(localized: "explain.pace", defaultValue: "Current 5-hour block: \(burn.value)\(detail). Block ends in \(ends).", bundle: bundle)
    }

    static func modelsExplanation(shares: [ModelShare], bySpend: Bool, bundle: Bundle = .main) -> String {
        guard !shares.isEmpty else { return String(localized: "explain.models.none", defaultValue: "No model has done work today.", bundle: bundle) }
        if shares.count == 1, let only = shares.first {
            return String(localized: "explain.models.single", defaultValue: "All of today's work went through \(only.name).", bundle: bundle)
        }
        let parts = shares.map { "\($0.name) \(percent(Int(($0.share * 100).rounded()), bundle: bundle))" }.joined(separator: ", ")
        return bySpend
            ? String(localized: "explain.models.bySpend", defaultValue: "Today's work by model, by spend: \(parts).", bundle: bundle)
            : String(localized: "explain.models.byTokens", defaultValue: "Today's work by model, by output tokens (no prices): \(parts).", bundle: bundle)
    }

    /// One block under the cursor: when it ran, how much it used, and how much of it is left.
    static func blockExplanation(_ block: CCUsageBlock, isActive: Bool, now: Date, bundle: Bundle = .main) -> String {
        let start = block.startTime.formatted(date: .omitted, time: .shortened)
        let end = block.endTime.formatted(date: .omitted, time: .shortened)
        let tokens = formatTokens(block.totalTokens)
        if isActive {
            let left = formatRemaining(max(0, block.endTime.timeIntervalSince(now)), bundle: bundle)
            return String(localized: "explain.block.active", defaultValue: "Active block \(start)–\(end): \(tokens) tokens so far; \(left) left in it.", bundle: bundle)
        }
        let lastActivity = (block.actualEndTime ?? block.endTime).formatted(date: .omitted, time: .shortened)
        return String(localized: "explain.block.finished", defaultValue: "Block \(start)–\(end): \(tokens) tokens; last activity at \(lastActivity).", bundle: bundle)
    }

    static func blocksExplanation(blocks: [CCUsageBlock], activeID: String?, bundle: Bundle = .main) -> String {
        guard !blocks.isEmpty else { return String(localized: "explain.blocks.none", defaultValue: "No 5-hour block has started today.", bundle: bundle) }
        let parts = blocks.map { block -> String in
            let start = block.startTime.formatted(date: .omitted, time: .shortened)
            let tokens = formatTokens(block.totalTokens)
            return block.id == activeID
                ? String(localized: "explain.blocks.active", defaultValue: "\(start) \(tokens) (active)", bundle: bundle)
                : "\(start) \(tokens)"
        }.joined(separator: ", ")
        return String(localized: "explain.blocks", defaultValue: "Today's 5-hour blocks by tokens: \(parts).", bundle: bundle)
    }
}
