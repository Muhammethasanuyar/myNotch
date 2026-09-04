import Foundation

/// The parts of `ccusage claude blocks --json` and `ccusage claude daily --json` the dashboard
/// shows. Every field the tool might drop is optional: the schema is the Rust code's, not the
/// (outdated) documentation's, and it may drift.
nonisolated struct CCUsageBlock: Decodable, Equatable, Sendable {
    struct TokenCounts: Decodable, Equatable, Sendable {
        var inputTokens = 0
        var outputTokens = 0
        var cacheCreationInputTokens = 0
        var cacheReadInputTokens = 0

        init(inputTokens: Int = 0, outputTokens: Int = 0, cacheCreationInputTokens: Int = 0, cacheReadInputTokens: Int = 0) {
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
            self.cacheCreationInputTokens = cacheCreationInputTokens
            self.cacheReadInputTokens = cacheReadInputTokens
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
            outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
            cacheCreationInputTokens = try c.decodeIfPresent(Int.self, forKey: .cacheCreationInputTokens) ?? 0
            cacheReadInputTokens = try c.decodeIfPresent(Int.self, forKey: .cacheReadInputTokens) ?? 0
        }

        private enum CodingKeys: String, CodingKey { case inputTokens, outputTokens, cacheCreationInputTokens, cacheReadInputTokens }
    }

    struct BurnRate: Decodable, Equatable, Sendable {
        var tokensPerMinute: Double?
        var tokensPerMinuteForIndicator: Double?
        var costPerHour: Double?
    }

    struct Projection: Decodable, Equatable, Sendable {
        var totalTokens: Double?
        var totalCost: Double?
        var remainingMinutes: Double?
    }

    let id: String
    let startTime: Date
    let endTime: Date
    var actualEndTime: Date?
    var isActive = false
    var isGap = false
    var tokenCounts = TokenCounts()
    var totalTokens = 0
    var costUSD: Double = 0
    var models: [String] = []
    var burnRate: BurnRate?
    var projection: Projection?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        startTime = try c.decode(Date.self, forKey: .startTime)
        endTime = try c.decode(Date.self, forKey: .endTime)
        actualEndTime = try c.decodeIfPresent(Date.self, forKey: .actualEndTime)
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        isGap = try c.decodeIfPresent(Bool.self, forKey: .isGap) ?? false
        tokenCounts = try c.decodeIfPresent(TokenCounts.self, forKey: .tokenCounts) ?? TokenCounts()
        totalTokens = try c.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
        costUSD = try c.decodeIfPresent(Double.self, forKey: .costUSD) ?? 0
        models = try c.decodeIfPresent([String].self, forKey: .models) ?? []
        burnRate = try c.decodeIfPresent(BurnRate.self, forKey: .burnRate)
        projection = try c.decodeIfPresent(Projection.self, forKey: .projection)
    }

    private enum CodingKeys: String, CodingKey {
        case id, startTime, endTime, actualEndTime, isActive, isGap, tokenCounts, totalTokens, costUSD, models, burnRate, projection
    }
}

nonisolated struct CCUsageBlocksReport: Decodable, Equatable, Sendable {
    var blocks: [CCUsageBlock] = []

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blocks = try c.decodeIfPresent([CCUsageBlock].self, forKey: .blocks) ?? []
    }

    private enum CodingKeys: String, CodingKey { case blocks }

    /// The block that is still running, ignoring the synthetic gap blocks.
    var activeBlock: CCUsageBlock? {
        blocks.first { $0.isActive && !$0.isGap }
    }
}

nonisolated struct CCUsageDay: Decodable, Equatable, Sendable {
    struct ModelBreakdown: Decodable, Equatable, Sendable {
        let modelName: String
        var inputTokens = 0
        var outputTokens = 0
        var cacheCreationTokens = 0
        var cacheReadTokens = 0
        var cost: Double = 0

        init(modelName: String, inputTokens: Int = 0, outputTokens: Int = 0, cacheCreationTokens: Int = 0, cacheReadTokens: Int = 0, cost: Double = 0) {
            self.modelName = modelName
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
            self.cacheCreationTokens = cacheCreationTokens
            self.cacheReadTokens = cacheReadTokens
            self.cost = cost
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            modelName = try c.decodeIfPresent(String.self, forKey: .modelName) ?? "unknown"
            inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
            outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
            cacheCreationTokens = try c.decodeIfPresent(Int.self, forKey: .cacheCreationTokens) ?? 0
            cacheReadTokens = try c.decodeIfPresent(Int.self, forKey: .cacheReadTokens) ?? 0
            cost = try c.decodeIfPresent(Double.self, forKey: .cost) ?? 0
        }

        private enum CodingKeys: String, CodingKey { case modelName, inputTokens, outputTokens, cacheCreationTokens, cacheReadTokens, cost }
    }

    let date: String
    var inputTokens = 0
    var outputTokens = 0
    var cacheCreationTokens = 0
    var cacheReadTokens = 0
    var totalTokens = 0
    var totalCost: Double = 0
    var modelsUsed: [String] = []
    var modelBreakdowns: [ModelBreakdown] = []

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        cacheCreationTokens = try c.decodeIfPresent(Int.self, forKey: .cacheCreationTokens) ?? 0
        cacheReadTokens = try c.decodeIfPresent(Int.self, forKey: .cacheReadTokens) ?? 0
        totalTokens = try c.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
        totalCost = try c.decodeIfPresent(Double.self, forKey: .totalCost) ?? 0
        modelsUsed = try c.decodeIfPresent([String].self, forKey: .modelsUsed) ?? []
        modelBreakdowns = try c.decodeIfPresent([ModelBreakdown].self, forKey: .modelBreakdowns) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case date, inputTokens, outputTokens, cacheCreationTokens, cacheReadTokens, totalTokens, totalCost, modelsUsed, modelBreakdowns
    }
}

nonisolated struct CCUsageDailyReport: Decodable, Equatable, Sendable {
    var daily: [CCUsageDay] = []

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        daily = try c.decodeIfPresent([CCUsageDay].self, forKey: .daily) ?? []
    }

    private enum CodingKeys: String, CodingKey { case daily }
}

/// What the module keeps from the two ccusage calls.
nonisolated struct CCUsageReport: Equatable, Sendable {
    var today: CCUsageDay?
    var activeBlock: CCUsageBlock?
    let generatedAt: Date
}

nonisolated enum CCUsageParser {
    /// ccusage writes RFC 3339 timestamps with milliseconds.
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { container in
            let text = try container.singleValueContainer().decode(String.self)
            guard let date = date(from: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath, debugDescription: "not an ISO 8601 date: \(text)"))
            }
            return date
        }
        return decoder
    }

    /// With or without fractional seconds. Formatters are not `Sendable`, so they are made per call;
    /// a report holds a handful of dates.
    static func date(from text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    static func blocks(from data: Data) throws -> CCUsageBlocksReport {
        try decoder().decode(CCUsageBlocksReport.self, from: data)
    }

    static func daily(from data: Data) throws -> CCUsageDailyReport {
        try decoder().decode(CCUsageDailyReport.self, from: data)
    }

    /// `--since` wants `YYYYMMDD` in local time.
    static func sinceArgument(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static let modelFamilies = ["opus", "sonnet", "haiku", "fable", "mythos"]

    /// Short model family for the breakdown bar: `claude-opus-4-7-20260301` → `Opus`.
    static func modelFamily(_ model: String) -> String {
        let lower = model.lowercased()
        for family in modelFamilies where lower.contains(family) {
            return family.prefix(1).uppercased() + family.dropFirst()
        }
        return model
    }

    /// Family and version, the way people say it: `claude-fable-5-1` → `Fable 5.1`,
    /// `claude-haiku-4-5-20251001` → `Haiku 4.5`, `claude-3-5-sonnet-20241022` → `Sonnet 3.5`.
    static func prettyModelName(_ model: String) -> String {
        var parts = model.lowercased().split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) { parts.removeLast() }   // release date
        guard let family = parts.first(where: { modelFamilies.contains($0) }) else { return model }
        let version = parts.filter { $0.allSatisfy(\.isNumber) }.joined(separator: ".")
        let name = family.prefix(1).uppercased() + family.dropFirst()
        return version.isEmpty ? name : "\(name) \(version)"
    }
}

/// How today's work splits across models: by spend when the tool could price it, by output
/// tokens when it could not — a bar of unpriced models would otherwise be all zeros.
nonisolated struct ModelShare: Equatable, Sendable {
    let name: String
    /// 0…1, all shares summing to one.
    let share: Double

    static func compute(_ breakdowns: [CCUsageDay.ModelBreakdown]) -> [ModelShare] {
        let byName = Dictionary(grouping: breakdowns, by: { CCUsageParser.prettyModelName($0.modelName) })
        let costs = byName.mapValues { $0.reduce(0) { $0 + $1.cost } }
        let weights = costs.values.reduce(0, +) > 0
            ? costs
            : byName.mapValues { Double($0.reduce(0) { $0 + $1.outputTokens }) }
        let total = weights.values.reduce(0, +)
        guard total > 0 else { return [] }
        return weights
            .map { ModelShare(name: $0.key, share: $0.value / total) }
            .sorted { $0.share > $1.share || ($0.share == $1.share && $0.name < $1.name) }
    }
}
