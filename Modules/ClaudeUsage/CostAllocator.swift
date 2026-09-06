import Foundation

/// Today's dollars as ccusage reports them: a total and a split by model. Unknown while ccusage
/// is not installed or has not answered yet.
nonisolated struct CostTable: Equatable, Sendable {
    var totalUSD: Double?
    var perModelUSD: [String: Double] = [:]
    var asOf: Date?

    static let unknown = CostTable()

    var isKnown: Bool { totalUSD != nil }

    /// From a `ccusage claude daily` row.
    init(day: CCUsageDay, asOf: Date) {
        totalUSD = day.totalCost
        perModelUSD = Dictionary(day.modelBreakdowns.map { ($0.modelName, $0.cost) }, uniquingKeysWith: +)
        self.asOf = asOf
    }

    init() {}
}

/// Spreads ccusage's per-model dollars over the tokens the native parser counted, so every block
/// and every hour can carry a price without the app knowing any list price. The weights are only
/// relative: they say how much dearer output is than input, not what either costs.
nonisolated enum CostAllocator {
    static let weights = (input: 1.0, output: 5.0, cacheWrite: 1.25, cacheRead: 0.1)

    static func weightedTokens(_ counts: CCUsageBlock.TokenCounts) -> Double {
        Double(counts.inputTokens) * weights.input
            + Double(counts.outputTokens) * weights.output
            + Double(counts.cacheCreationInputTokens) * weights.cacheWrite
            + Double(counts.cacheReadInputTokens) * weights.cacheRead
    }

    /// Dollars per weighted token, per model, calibrated to ccusage's own daily figures. A model
    /// ccusage could not price (or one not in today's table) scales to zero, which the card shows
    /// as "—" the way it always has.
    static func scales(daily: CostTable, todaysTokensByModel: [String: CCUsageBlock.TokenCounts]) -> [String: Double] {
        var scales: [String: Double] = [:]
        for (model, counts) in todaysTokensByModel {
            let weighted = weightedTokens(counts)
            guard weighted > 0, let dollars = daily.perModelUSD[model], dollars > 0 else { continue }
            scales[model] = dollars / weighted
        }
        return scales
    }

    static func cost(_ counts: CCUsageBlock.TokenCounts, model: String?, scales: [String: Double]) -> Double {
        guard let model, let scale = scales[model] else { return 0 }
        return weightedTokens(counts) * scale
    }
}
