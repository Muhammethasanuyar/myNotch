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

/// Pure decisions of the module, kept out of the view model so they can be tested.
nonisolated enum ClaudeUsageRules {
    /// Live while Claude is working, and while the 5-hour window is past the warning threshold so
    /// the number stays in view when it matters.
    static func activity(isWorking: Bool, fiveHour: UsageWindow?, thresholds: UsageThresholds) -> ModuleActivity {
        if isWorking { return .live }
        if let fiveHour, fiveHour.utilization >= thresholds.warning { return .live }
        return .idle
    }

    static func crossingEvent(_ crossing: ThresholdCrossing, moduleID: String, now: Date) -> NotchEvent {
        let percent = Int((crossing.window.utilization * 100).rounded())
        var detail = crossing.threshold >= 0.95 ? "Nearly exhausted" : "Slow down"
        if let remaining = crossing.window.remaining(at: now) {
            detail += " — resets in \(formatRemaining(remaining))"
        }
        return NotchEvent(
            moduleID: moduleID,
            title: "\(crossing.kind.title) limit at \(percent)%",
            detail: detail,
            symbolName: crossing.threshold >= 0.95 ? "exclamationmark.triangle.fill" : "gauge.with.needle",
            duration: 4
        )
    }

    static func resetEvent(_ kind: UsageWindowKind, moduleID: String) -> NotchEvent {
        NotchEvent(moduleID: moduleID, title: "\(kind.title) window reset", detail: "Fresh allowance", symbolName: "arrow.counterclockwise", duration: 3)
    }

    /// What the compact wing shows: the 5-hour percentage when known, else today's cost.
    static func compactLabel(fiveHour: UsageWindow?, todayCost: Double?) -> String? {
        if let fiveHour { return "\(Int((fiveHour.utilization * 100).rounded()))%" }
        if let todayCost { return formatCost(todayCost) }
        return nil
    }

    /// "2d 3h", "1h 20m", "45m", "<1m".
    static func formatRemaining(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        let rest = minutes % 60
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return rest > 0 ? "\(hours)h \(rest)m" : "\(hours)h" }
        return minutes > 0 ? "\(minutes)m" : "<1m"
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
    /// - Returns: the headline ("3.3K tok/min") and, when the tool could price it, the money part.
    static func burnDescription(tokensPerMinute: Double?, costPerHour: Double?, projectedCost: Double?) -> (value: String, detail: String?)? {
        guard let tokensPerMinute, tokensPerMinute > 0 else { return nil }
        let value = "\(formatTokens(Int(tokensPerMinute.rounded()))) tok/min"
        guard let costPerHour, costPerHour > 0 else { return (value, nil) }
        var detail = "\(formatCost(costPerHour))/h"
        if let projectedCost, projectedCost > 0 { detail += " · ≈\(formatCost(projectedCost)) by reset" }
        return (value, detail)
    }

    // MARK: Explanations shown while the cursor rests on an indicator

    static func ringExplanation(kind: UsageWindowKind, window: UsageWindow?, now: Date) -> String {
        guard let window else { return "\(kind.title) limit — Anthropic has not reported it yet." }
        let used = Int((window.utilization * 100).rounded())
        var text = "\(kind.title) limit — \(used)% of the allowance used"
        if let remaining = window.remaining(at: now) {
            text += ", resets in \(formatRemaining(remaining))"
        }
        if let elapsed = window.elapsedFraction(kind: kind, at: now) {
            text += ". Outer arc: \(Int((elapsed * 100).rounded()))% of the window has passed."
        } else {
            text += "."
        }
        return text
    }

    static func spendExplanation(day: CCUsageDay) -> String {
        let unpriced = day.modelBreakdowns.filter { $0.cost == 0 && ($0.outputTokens > 0 || $0.inputTokens > 0) }
            .map { CCUsageParser.prettyModelName($0.modelName) }
        var text = day.totalCost > 0 ? "Spent today: \(formatCost(day.totalCost)), priced by ccusage's offline table." : "Spend today, as far as ccusage can price it."
        if !unpriced.isEmpty {
            text += " No price is known for \(unpriced.joined(separator: ", ")) — its tokens count as $0."
        }
        return text
    }

    static func tokensExplanation(day: CCUsageDay) -> String {
        "Tokens today: \(formatTokens(day.totalTokens)) — \(formatTokens(day.inputTokens)) in, \(formatTokens(day.outputTokens)) out, \(formatTokens(day.cacheReadTokens + day.cacheCreationTokens)) cache."
    }

    static func paceExplanation(tokensPerMinute: Double?, costPerHour: Double?, projectedCost: Double?, blockEnd: Date, now: Date) -> String {
        guard let burn = burnDescription(tokensPerMinute: tokensPerMinute, costPerHour: costPerHour, projectedCost: projectedCost) else {
            return "Pace of the current 5-hour block."
        }
        var text = "Current 5-hour block: \(burn.value)"
        if let detail = burn.detail { text += ", \(detail)" }
        text += ". Block ends in \(formatRemaining(max(0, blockEnd.timeIntervalSince(now))))."
        return text
    }

    static func modelsExplanation(shares: [ModelShare], bySpend: Bool) -> String {
        guard !shares.isEmpty else { return "No model has done work today." }
        if shares.count == 1, let only = shares.first { return "All of today's work went through \(only.name)." }
        let parts = shares.map { "\($0.name) \(Int(($0.share * 100).rounded()))%" }.joined(separator: ", ")
        return "Today's work by model, \(bySpend ? "by spend" : "by output tokens (no prices)"): \(parts)."
    }

    /// Ring colour by fill: calm, then warning, then critical.
    static func level(for utilization: Double, thresholds: UsageThresholds) -> Int {
        if utilization >= thresholds.critical { return 2 }
        if utilization >= thresholds.warning { return 1 }
        return 0
    }
}
