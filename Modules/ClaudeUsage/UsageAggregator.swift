// Adapted from https://github.com/ccusage/ccusage (MIT): the dedupe winner rule and how a day's
// and a block's totals are assembled from entries.

import Foundation

/// Where a report's dollars came from.
nonisolated enum CostSource: Equatable, Sendable {
    /// No ccusage: every cost field is zero and the card says so.
    case unavailable
    case ccusage(asOf: Date)
}

/// Turns the ledger's entries into the report the dashboard already understands.
nonisolated enum UsageAggregator {
    /// The same turn can be written more than once (replays, summaries, a sub-agent's copy).
    /// One survives: the one that is not a sidechain, then the one with more tokens.
    static func dedupe(_ entries: [UsageEntry]) -> [UsageEntry] {
        var kept: [UsageEntry] = []
        var indexByKey: [DedupeKey: Int] = [:]
        var indexByMessage: [DedupeKey: Int] = [:]
        for entry in entries {
            guard let key = entry.dedupeKey else {
                kept.append(entry)
                continue
            }
            let messageKey = DedupeKey(messageID: key.messageID, requestID: nil, sessionID: key.sessionID)
            let existing = indexByKey[key] ?? (entry.isSidechain || indexByMessage[messageKey].map { kept[$0].isSidechain } == true ? indexByMessage[messageKey] : nil)
            if let existing {
                if wins(entry, over: kept[existing]) { kept[existing] = entry }
            } else {
                kept.append(entry)
                indexByKey[key] = kept.count - 1
                indexByMessage[messageKey] = kept.count - 1
            }
        }
        return kept
    }

    private static func wins(_ candidate: UsageEntry, over current: UsageEntry) -> Bool {
        if candidate.isSidechain != current.isSidechain { return !candidate.isSidechain }
        return candidate.totalTokens > current.totalTokens
    }

    /// The report for `now`: today's totals and model split, today's blocks, the running block.
    static func report(entries: [UsageEntry], now: Date, calendar: Calendar = .current, cost: CostTable = .unknown) -> CCUsageReport {
        let deduped = dedupe(entries).sorted { $0.timestamp < $1.timestamp }
        let blocks = BlockCalculator.identifySessionBlocks(deduped)

        let todayStart = calendar.startOfDay(for: now)
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now.addingTimeInterval(86_400)
        let todayEntries = deduped.filter { $0.timestamp >= todayStart && $0.timestamp < todayEnd }
        let tokensByModel = tokens(byModel: todayEntries)
        let scales = cost.isKnown ? CostAllocator.scales(daily: cost, todaysTokensByModel: tokensByModel) : [:]

        let day = today(entries: todayEntries, tokensByModel: tokensByModel, cost: cost, scales: scales, now: now, calendar: calendar)
        let todayBlocks = blocks
            .filter { !$0.isGap && calendar.isDate($0.startTime, inSameDayAs: now) }
            .map { convert($0, now: now, scales: scales) }
        // Taken from every block, not today's: a block that began yesterday evening is still the
        // one running at half past midnight.
        let active = blocks.first { $0.isActive(now: now) }.map { convert($0, now: now, scales: scales) }

        var report = CCUsageReport(today: day, todayBlocks: todayBlocks, activeBlock: active, generatedAt: now)
        report.costSource = cost.asOf.map(CostSource.ccusage) ?? .unavailable
        return report
    }

    static func tokens(byModel entries: [UsageEntry]) -> [String: CCUsageBlock.TokenCounts] {
        entries.reduce(into: [:]) { result, entry in
            guard let model = entry.model else { return }
            var counts = result[model] ?? CCUsageBlock.TokenCounts()
            counts.inputTokens += entry.inputTokens
            counts.outputTokens += entry.outputTokens
            counts.cacheCreationInputTokens += entry.cacheCreationTokens
            counts.cacheReadInputTokens += entry.cacheReadTokens
            result[model] = counts
        }
    }

    private static func today(entries: [UsageEntry], tokensByModel: [String: CCUsageBlock.TokenCounts], cost: CostTable, scales: [String: Double], now: Date, calendar: Calendar) -> CCUsageDay {
        var day = CCUsageDay(date: dateString(for: now, calendar: calendar))
        for entry in entries {
            day.inputTokens += entry.inputTokens
            day.outputTokens += entry.outputTokens
            day.cacheCreationTokens += entry.cacheCreationTokens
            day.cacheReadTokens += entry.cacheReadTokens
        }
        day.totalTokens = day.inputTokens + day.outputTokens + day.cacheCreationTokens + day.cacheReadTokens
        day.totalCost = cost.totalUSD ?? 0
        day.modelBreakdowns = tokensByModel.map { model, counts in
            CCUsageDay.ModelBreakdown(
                modelName: model,
                inputTokens: counts.inputTokens,
                outputTokens: counts.outputTokens,
                cacheCreationTokens: counts.cacheCreationInputTokens,
                cacheReadTokens: counts.cacheReadInputTokens,
                cost: cost.perModelUSD[model] ?? 0
            )
        }
        .sorted { lhs, rhs in
            if lhs.cost != rhs.cost { return lhs.cost > rhs.cost }
            let lhsTokens = lhs.inputTokens + lhs.outputTokens + lhs.cacheCreationTokens + lhs.cacheReadTokens
            let rhsTokens = rhs.inputTokens + rhs.outputTokens + rhs.cacheCreationTokens + rhs.cacheReadTokens
            return lhsTokens != rhsTokens ? lhsTokens > rhsTokens : lhs.modelName < rhs.modelName
        }
        day.modelsUsed = day.modelBreakdowns.map(\.modelName)
        return day
    }

    /// "2026-09-06" in the local calendar, the way `ccusage daily` labels a day.
    static func dateString(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func convert(_ block: UsageBlock, now: Date, scales: [String: Double]) -> CCUsageBlock {
        let costUSD: Double? = scales.isEmpty ? nil : tokens(byModel: block.entries).reduce(0) { $0 + CostAllocator.cost($1.value, model: $1.key, scales: scales) }
        let isActive = block.isActive(now: now)
        let burnRate = isActive ? BlockCalculator.burnRate(block, costUSD: costUSD) : nil
        return CCUsageBlock(
            id: block.id,
            startTime: block.startTime,
            endTime: block.endTime,
            actualEndTime: block.actualEndTime,
            isActive: isActive,
            isGap: block.isGap,
            tokenCounts: block.tokenCounts,
            totalTokens: block.totalTokens,
            costUSD: costUSD ?? 0,
            models: block.models,
            burnRate: burnRate,
            projection: BlockCalculator.projection(block, burnRate: burnRate, costUSD: costUSD, now: now)
        )
    }
}
