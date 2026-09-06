// Adapted from https://github.com/ccusage/ccusage (MIT): which session-log lines count as usage,
// the cache-creation rule, the `<synthetic>` and `-fast` model rules, the validity filters and
// the fields the dedupe key is built from.

import Foundation

/// One assistant turn's token usage, as written to `~/.claude/projects/**/*.jsonl`.
nonisolated struct UsageEntry: Equatable, Sendable {
    let timestamp: Date
    let sessionID: String
    let requestID: String?
    let messageID: String?
    /// `nil` for `<synthetic>` placeholders; speed-boosted calls carry a `-fast` suffix.
    let model: String?
    let isSidechain: Bool
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    /// Claude Code has not written this for a long time; kept for parity with `--mode auto`.
    let costUSD: Double?

    var totalTokens: Int { inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens }

    var tokenCounts: CCUsageBlock.TokenCounts {
        CCUsageBlock.TokenCounts(inputTokens: inputTokens, outputTokens: outputTokens, cacheCreationInputTokens: cacheCreationTokens, cacheReadInputTokens: cacheReadTokens)
    }

    var dedupeKey: DedupeKey? {
        messageID.map { DedupeKey(messageID: $0, requestID: requestID, sessionID: sessionID) }
    }
}

nonisolated struct DedupeKey: Hashable, Sendable {
    let messageID: String
    let requestID: String?
    let sessionID: String
}

/// What one pass over a stretch of a log yields.
nonisolated struct LogChunk: Equatable, Sendable {
    var entries: [UsageEntry] = []
    /// Fields for the "working on…" header, from the newest lines that carry them.
    var tail = SessionTail()
    /// Bytes consumed: up to and including the last newline, so a line still being written waits
    /// for the next read instead of being half-parsed.
    var consumed = 0
}

nonisolated enum SessionLogParser {
    /// Only lines with a usage object are decoded; that is about a quarter of a session log.
    static let usageMarker = Data("\"usage\":{".utf8)
    /// `custom-title` lines rename the session; they are rare and small.
    static let titleMarker = Data("custom-title".utf8)

    /// Parses every complete line of `data`, which must start at a line boundary.
    /// - Parameter fallbackSessionID: used when a line carries no `sessionId` — the file's name.
    static func parse(_ data: Data, fallbackSessionID: String) -> LogChunk {
        var chunk = LogChunk()
        let decoder = JSONDecoder()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()

        var lineStart = data.startIndex
        while let newline = data[lineStart...].firstIndex(of: 0x0A) {
            let line = data[lineStart..<newline]
            chunk.consumed = newline - data.startIndex + 1
            lineStart = newline + 1
            guard !line.isEmpty else { continue }
            let hasUsage = line.range(of: usageMarker) != nil
            let hasTitle = !hasUsage && line.range(of: titleMarker) != nil
            guard hasUsage || hasTitle else { continue }
            guard let raw = try? decoder.decode(RawEntry.self, from: line) else { continue }

            if let cwd = raw.cwd, !cwd.isEmpty { chunk.tail.cwd = cwd }
            if let session = raw.sessionId, !session.isEmpty { chunk.tail.sessionID = session }
            if raw.type == "custom-title", let title = raw.customTitle, !title.isEmpty {
                chunk.tail.customTitle = title
            }
            guard hasUsage, let entry = entry(from: raw, fallbackSessionID: fallbackSessionID, fractional: fractional, plain: plain) else { continue }
            chunk.tail.lastTimestamp = entry.timestamp
            if let model = entry.model { chunk.tail.lastModel = model }
            chunk.entries.append(entry)
        }
        return chunk
    }

    /// The entry a decoded line describes, or `nil` when ccusage would skip the line too.
    static func entry(from raw: RawEntry, fallbackSessionID: String, fractional: ISO8601DateFormatter, plain: ISO8601DateFormatter) -> UsageEntry? {
        guard raw.type == "assistant", let message = raw.message, let usage = message.usage else { return nil }
        guard let stamp = raw.timestamp, let timestamp = fractional.date(from: stamp) ?? plain.date(from: stamp) else { return nil }
        if let version = raw.version, !(version.first?.isNumber ?? false) { return nil }
        if let session = raw.sessionId, session.isEmpty { return nil }
        if let request = raw.requestId, request.isEmpty { return nil }
        if let id = message.id, id.isEmpty { return nil }
        if let model = message.model, model.isEmpty { return nil }

        var model: String? = message.model
        if model == "<synthetic>" { model = nil }
        if let name = model, usage.speed == "fast" { model = name + "-fast" }
        let cacheCreation = usage.cacheCreation.map { ($0.ephemeral5m ?? 0) + ($0.ephemeral1h ?? 0) } ?? usage.cacheCreationInputTokens ?? 0

        return UsageEntry(
            timestamp: timestamp,
            sessionID: raw.sessionId ?? fallbackSessionID,
            requestID: raw.requestId,
            messageID: message.id,
            model: model,
            isSidechain: raw.isSidechain ?? false,
            inputTokens: usage.inputTokens ?? 0,
            outputTokens: usage.outputTokens ?? 0,
            cacheCreationTokens: cacheCreation,
            cacheReadTokens: usage.cacheReadInputTokens ?? 0,
            costUSD: raw.costUSD
        )
    }

    // MARK: Raw shape

    /// The keys read from a log line; everything is optional so an unexpected line never fails
    /// the file. Written out by hand: the top level is camelCase, `usage` is snake_case.
    struct RawEntry: Decodable {
        var type: String?
        var timestamp: String?
        var sessionId: String?
        var requestId: String?
        var version: String?
        var isSidechain: Bool?
        var costUSD: Double?
        var cwd: String?
        var customTitle: String?
        var message: RawMessage?

        struct RawMessage: Decodable {
            var id: String?
            var model: String?
            var usage: RawUsage?

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                id = try? c.decodeIfPresent(String.self, forKey: .id)
                model = try? c.decodeIfPresent(String.self, forKey: .model)
                usage = try? c.decodeIfPresent(RawUsage.self, forKey: .usage)
            }

            private enum CodingKeys: String, CodingKey { case id, model, usage }
        }

        struct RawUsage: Decodable {
            var inputTokens: Int?
            var outputTokens: Int?
            var cacheCreationInputTokens: Int?
            var cacheReadInputTokens: Int?
            var cacheCreation: RawCacheCreation?
            var speed: String?

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                inputTokens = try? c.decodeIfPresent(Int.self, forKey: .inputTokens)
                outputTokens = try? c.decodeIfPresent(Int.self, forKey: .outputTokens)
                cacheCreationInputTokens = try? c.decodeIfPresent(Int.self, forKey: .cacheCreationInputTokens)
                cacheReadInputTokens = try? c.decodeIfPresent(Int.self, forKey: .cacheReadInputTokens)
                cacheCreation = try? c.decodeIfPresent(RawCacheCreation.self, forKey: .cacheCreation)
                speed = try? c.decodeIfPresent(String.self, forKey: .speed)
            }

            private enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
                case cacheCreationInputTokens = "cache_creation_input_tokens"
                case cacheReadInputTokens = "cache_read_input_tokens"
                case cacheCreation = "cache_creation"
                case speed
            }
        }

        struct RawCacheCreation: Decodable {
            var ephemeral5m: Int?
            var ephemeral1h: Int?

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                ephemeral5m = try? c.decodeIfPresent(Int.self, forKey: .ephemeral5m)
                ephemeral1h = try? c.decodeIfPresent(Int.self, forKey: .ephemeral1h)
            }

            private enum CodingKeys: String, CodingKey {
                case ephemeral5m = "ephemeral_5m_input_tokens"
                case ephemeral1h = "ephemeral_1h_input_tokens"
            }
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try? c.decodeIfPresent(String.self, forKey: .type)
            timestamp = try? c.decodeIfPresent(String.self, forKey: .timestamp)
            sessionId = try? c.decodeIfPresent(String.self, forKey: .sessionId)
            requestId = try? c.decodeIfPresent(String.self, forKey: .requestId)
            version = try? c.decodeIfPresent(String.self, forKey: .version)
            isSidechain = try? c.decodeIfPresent(Bool.self, forKey: .isSidechain)
            costUSD = try? c.decodeIfPresent(Double.self, forKey: .costUSD)
            cwd = try? c.decodeIfPresent(String.self, forKey: .cwd)
            customTitle = try? c.decodeIfPresent(String.self, forKey: .customTitle)
            message = try? c.decodeIfPresent(RawMessage.self, forKey: .message)
        }

        private enum CodingKeys: String, CodingKey {
            case type, timestamp, sessionId, requestId, version, isSidechain, costUSD, cwd, customTitle, message
        }
    }
}
