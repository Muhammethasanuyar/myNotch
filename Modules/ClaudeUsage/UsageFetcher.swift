import Foundation
import os

// Adapted from https://github.com/ericjypark/codex-island (MIT) and
// https://github.com/stevemcqueenz/claude-notch-tracker (MIT): endpoint, headers, status mapping and
// the tolerant window parsing including the per-model weekly split.

/// Talks to Anthropic's undocumented usage endpoint — the only place the official 5-hour and weekly
/// percentages exist. Privacy: the request carries the Claude Code access token and nothing else.
nonisolated enum UsageFetcher {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    /// The endpoint is gated on a CLI-style agent; kept in one place because it will need bumps.
    static let userAgent = "claude-code/2.1.121"

    enum Outcome: Equatable, Sendable {
        case usage(UsageSnapshot)
        /// 401: the token is not accepted (expired or revoked).
        case unauthorized
        /// 403: the token lacks a scope; only a fresh `claude /login` helps.
        case reauthRequired
        /// 429, or a 200 whose body is a rate-limit error.
        case rateLimited
        case failed(String)
    }

    static func request(token: String) -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    static func fetch(token: String, session: URLSession, now: Date = Date()) async -> Outcome {
        do {
            let (data, response) = try await session.data(for: request(token: token))
            guard let http = response as? HTTPURLResponse else { return .failed("no HTTP response") }
            return outcome(status: http.statusCode, body: data, now: now)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // MARK: Parsing (pure)

    static func outcome(status: Int, body: Data, now: Date) -> Outcome {
        switch status {
        case 401: return .unauthorized
        case 403: return .reauthRequired
        case 429: return .rateLimited
        case 200: break
        default: return .failed("HTTP \(status)")
        }
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return .failed("unreadable body")
        }
        logShape(object)
        if let error = object["error"] as? [String: Any], error["type"] as? String == "rate_limit_error" {
            return .rateLimited
        }
        guard let snapshot = parseSnapshot(object, now: now) else { return .failed("no usage windows in response") }
        return .usage(snapshot)
    }

    private static let log = Logger(subsystem: "com.emre.mynotch", category: "usage-shape")

    /// Records the *shape* of the response — key names, model scopes, percentages — never the
    /// token or anything identifying. The endpoint is undocumented; this is how new windows
    /// (per-model limits) get noticed.
    static func logShape(_ object: [String: Any]) {
        let keys = object.keys.sorted().joined(separator: ",")
        var limits = "-"
        if let array = object["limits"] as? [[String: Any]],
           let data = try? JSONSerialization.data(withJSONObject: array, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            limits = text
        }
        let windows = object.filter { $0.key.hasPrefix("seven_day") || $0.key.hasPrefix("five_hour") }
            .map { key, value -> String in
                let window = value as? [String: Any]
                return "\(key)=\(((window?["utilization"] ?? window?["used_percent"]) as? NSNumber)?.stringValue ?? "?")@\(window?["resets_at"] ?? "?")"
            }
            .sorted()
            .joined(separator: " ")
        log.debug("usage keys: \(keys, privacy: .public) windows: \(windows, privacy: .public) limits: \(limits, privacy: .public)")
    }

    /// `five_hour` and `seven_day` at the top level; some plans split the week into
    /// `seven_day_opus` / `seven_day_sonnet`, in which case the fullest one stands for the week.
    static func parseSnapshot(_ object: [String: Any], now: Date) -> UsageSnapshot? {
        var weekly: [String: UsageWindow] = [:]
        for (key, value) in object where key.hasPrefix("seven_day_") {
            if let window = parseWindow(value) {
                weekly[String(key.dropFirst("seven_day_".count))] = window
            }
        }
        let sevenDay = parseWindow(object["seven_day"]) ?? weekly.values.max { $0.utilization < $1.utilization }
        let fiveHour = parseWindow(object["five_hour"])
        let scoped = parseScopedLimits(object)
        guard fiveHour != nil || sevenDay != nil || !scoped.isEmpty else { return nil }
        return UsageSnapshot(fiveHour: fiveHour, sevenDay: sevenDay, weeklyByModel: weekly, scopedLimits: scoped, fetchedAt: now)
    }

    /// The `limits[]` entries that name a model or surface. Entries with a null scope repeat the
    /// account windows (`session`, `weekly_all`) and are skipped; `percent` is 0–100 like the rest.
    static func parseScopedLimits(_ object: [String: Any]) -> [ScopedLimit] {
        guard let entries = object["limits"] as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard let scope = entry["scope"] as? [String: Any] else { return nil }
            let model = (scope["model"] as? [String: Any])?["display_name"] as? String
            let surface = scope["surface"] as? String
            guard let name = model ?? surface, !name.isEmpty,
                  let raw = (entry["percent"] ?? entry["utilization"]) as? NSNumber else { return nil }
            let kind = (entry["kind"] as? String) ?? (entry["group"] as? String) ?? "scoped"
            return ScopedLimit(
                name: name,
                kind: kind,
                windowKind: kind.localizedCaseInsensitiveContains("week") ? .sevenDay : .fiveHour,
                window: UsageWindow(utilization: min(1, max(0, raw.doubleValue / 100)), resetsAt: parseDate(entry["resets_at"] ?? entry["resetsAt"]))
            )
        }
    }

    /// `utilization` (or `used_percent`) is a 0–100 percentage — never a fraction, even at 0.5 %.
    static func parseWindow(_ value: Any?) -> UsageWindow? {
        guard let window = value as? [String: Any] else { return nil }
        guard let raw = (window["utilization"] ?? window["used_percent"]) as? NSNumber else { return nil }
        let utilization = min(1, max(0, raw.doubleValue / 100))
        return UsageWindow(utilization: utilization, resetsAt: parseDate(window["resets_at"] ?? window["resetsAt"]))
    }

    /// Epoch seconds or ISO 8601 with or without fractional seconds.
    static func parseDate(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        guard let text = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
