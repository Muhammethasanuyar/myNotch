// Adapted from https://github.com/ccusage/ccusage (MIT): identify_session_blocks (floor to the
// hour, five-hour windows, gap blocks), the activity rule, calculate_burn_rate and
// project_block_usage.

import Foundation

/// A five-hour billing window and the turns that fell into it.
nonisolated struct UsageBlock: Equatable, Sendable {
    let startTime: Date
    let endTime: Date
    var entries: [UsageEntry] = []
    var isGap = false

    var id: String { isGap ? "gap-" + BlockCalculator.identifier(for: startTime) : BlockCalculator.identifier(for: startTime) }
    var actualEndTime: Date? { entries.last?.timestamp }

    /// Still running: something happened within the window's length and the window is not over.
    func isActive(now: Date, duration: TimeInterval = BlockCalculator.sessionDuration) -> Bool {
        guard !isGap, let last = actualEndTime else { return false }
        return now.timeIntervalSince(last) < duration && now < endTime
    }

    var tokenCounts: CCUsageBlock.TokenCounts {
        entries.reduce(into: CCUsageBlock.TokenCounts()) { counts, entry in
            counts.inputTokens += entry.inputTokens
            counts.outputTokens += entry.outputTokens
            counts.cacheCreationInputTokens += entry.cacheCreationTokens
            counts.cacheReadInputTokens += entry.cacheReadTokens
        }
    }

    var totalTokens: Int { entries.reduce(0) { $0 + $1.totalTokens } }

    /// Distinct model names in order of first use.
    var models: [String] {
        var seen: Set<String> = []
        return entries.compactMap { entry in
            guard let model = entry.model, !seen.contains(model) else { return nil }
            seen.insert(model)
            return model
        }
    }
}

nonisolated enum BlockCalculator {
    static let sessionDuration: TimeInterval = 5 * 3600

    /// Blocks start on the hour, in UTC — the same as ccusage, so a block id here matches its id there.
    static func floorToHour(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
    }

    /// "2026-09-04T12:00:00.000Z", the way ccusage names a block.
    static func identifier(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// Walks the turns in time order: a block closes when a turn falls more than `duration` after
    /// the block's start or after the previous turn; a silence longer than `duration` also leaves
    /// a gap block between the two real ones.
    static func identifySessionBlocks(_ entries: [UsageEntry], duration: TimeInterval = sessionDuration) -> [UsageBlock] {
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        var blocks: [UsageBlock] = []
        var current: UsageBlock?

        for entry in sorted {
            if var block = current {
                let last = block.entries.last?.timestamp ?? block.startTime
                let sinceStart = entry.timestamp.timeIntervalSince(block.startTime)
                let sinceLast = entry.timestamp.timeIntervalSince(last)
                if sinceStart > duration || sinceLast > duration {
                    blocks.append(block)
                    if sinceLast > duration {
                        blocks.append(UsageBlock(startTime: block.endTime, endTime: floorToHour(entry.timestamp), entries: [], isGap: true))
                    }
                    let start = floorToHour(entry.timestamp)
                    block = UsageBlock(startTime: start, endTime: start.addingTimeInterval(duration))
                }
                block.entries.append(entry)
                current = block
            } else {
                let start = floorToHour(entry.timestamp)
                current = UsageBlock(startTime: start, endTime: start.addingTimeInterval(duration), entries: [entry])
            }
        }
        if let current { blocks.append(current) }
        return blocks
    }

    /// Tokens per minute between the block's first and last turn (not per minute of the window);
    /// the indicator rate leaves cache tokens out. `nil` for a block with no span yet.
    static func burnRate(_ block: UsageBlock, costUSD: Double?) -> CCUsageBlock.BurnRate? {
        guard let first = block.entries.first?.timestamp, let last = block.entries.last?.timestamp else { return nil }
        let minutes = last.timeIntervalSince(first) / 60
        guard minutes > 0 else { return nil }
        let counts = block.tokenCounts
        return CCUsageBlock.BurnRate(
            tokensPerMinute: Double(block.totalTokens) / minutes,
            tokensPerMinuteForIndicator: Double(counts.inputTokens + counts.outputTokens) / minutes,
            costPerHour: costUSD.map { $0 / minutes * 60 }
        )
    }

    /// Where the running block lands if the pace holds until the window closes.
    static func projection(_ block: UsageBlock, burnRate: CCUsageBlock.BurnRate?, costUSD: Double?, now: Date) -> CCUsageBlock.Projection? {
        guard block.isActive(now: now), let rate = burnRate, let perMinute = rate.tokensPerMinute else { return nil }
        let remaining = (block.endTime.timeIntervalSince(now) / 60).rounded()
        let totalTokens = Double(block.totalTokens) + perMinute * remaining
        let totalCost: Double? = if let cost = costUSD, let perHour = rate.costPerHour {
            ((cost + perHour / 60 * remaining) * 100).rounded() / 100
        } else {
            nil
        }
        return CCUsageBlock.Projection(totalTokens: totalTokens, totalCost: totalCost, remainingMinutes: remaining)
    }
}
