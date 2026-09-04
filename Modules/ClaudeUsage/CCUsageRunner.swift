import Foundation

/// How `ccusage` gets launched, for the dashboard's footnote.
nonisolated enum CCUsageLauncher: Equatable, Sendable {
    /// A `ccusage` executable (Homebrew, npm -g, bun).
    case binary(URL)
    /// `npx --yes ccusage@20` through the `npx` found here; the first run downloads the package.
    case npx(URL)

    var description: String {
        switch self {
        case .binary(let url): return url.path
        case .npx(let url): return "\(url.path) \(CCUsageRunner.npxPackage)"
        }
    }

    /// The directory the tool lives in, which the child's PATH must include (npx needs `node`).
    var binDirectory: String {
        switch self {
        case .binary(let url), .npx(let url): return url.deletingLastPathComponent().path
        }
    }
}

nonisolated enum CCUsageState: Equatable, Sendable {
    case unknown
    case ready(CCUsageLauncher)
    /// Neither a `ccusage` executable nor `npx` is installed.
    case notInstalled
    case failed(String)
}

nonisolated enum CCUsageError: Error, Equatable {
    case exit(status: Int32, message: String)
}

/// Runs the community cost tool and decodes its JSON. Cost maths (cache tiers, per-model pricing)
/// is deliberately not reimplemented here.
///
/// Privacy: `--offline` keeps ccusage from fetching price tables, so nothing leaves the machine.
/// The `npx` path does contact the npm registry to download the pinned package the first time.
nonisolated enum CCUsageRunner {
    /// Pinned to the major we parsed against; `@latest` would re-resolve on every call.
    static let npxPackage = "ccusage@20"
    static let timeout: TimeInterval = 90
    static let pathOverrideKey = "ccusagePath"

    /// Where a LaunchServices-launched app cannot see tools: its PATH is just the system dirs, so
    /// Homebrew, bun, npm -g and every nvm node version are checked explicitly.
    static func candidateDirectories(home: String, nodeVersions: [String] = []) -> [String] {
        let fixed = ["/opt/homebrew/bin", "/usr/local/bin", home + "/.bun/bin", home + "/.npm-global/bin", home + "/.local/bin"]
        let nvm = nodeVersions
            .sorted { lhs, rhs in lhs.compare(rhs, options: .numeric) == .orderedDescending }
            .map { home + "/.nvm/versions/node/\($0)/bin" }
        return fixed + nvm
    }

    static func installedNodeVersions(home: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: home + "/.nvm/versions/node")) ?? []
    }

    /// A `ccusage` executable wins; otherwise `npx`. `nil` means neither exists.
    static func locate(home: String = NSHomeDirectory(),
                       override: String? = UserDefaults.standard.string(forKey: pathOverrideKey),
                       directories: [String]? = nil,
                       isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> CCUsageLauncher? {
        if let override, !override.isEmpty, isExecutable(override) {
            return .binary(URL(fileURLWithPath: override))
        }
        let dirs = directories ?? candidateDirectories(home: home, nodeVersions: installedNodeVersions(home: home))
        if let dir = dirs.first(where: { isExecutable($0 + "/ccusage") }) {
            return .binary(URL(fileURLWithPath: dir + "/ccusage"))
        }
        if let dir = dirs.first(where: { isExecutable($0 + "/npx") }) {
            return .npx(URL(fileURLWithPath: dir + "/npx"))
        }
        return nil
    }

    struct Invocation: Equatable, Sendable {
        let executable: URL
        let arguments: [String]
        let environment: [String: String]
    }

    /// Builds the command line for one ccusage subcommand, with a PATH the launcher can work from
    /// (npx's shebang needs `node` on it) and the config dir override ccusage understands.
    static func invocation(_ launcher: CCUsageLauncher, command: [String], home: String, configDirectory: String?) -> Invocation {
        var environment = [
            "HOME": home,
            "NO_COLOR": "1",
            "npm_config_update_notifier": "false",
            "PATH": "\(launcher.binDirectory):/usr/bin:/bin:/usr/sbin:/sbin"
        ]
        if let configDirectory, !configDirectory.isEmpty {
            environment[ClaudeCredentials.configDirectoryKey] = configDirectory
        }
        switch launcher {
        case .binary(let url):
            return Invocation(executable: url, arguments: command, environment: environment)
        case .npx(let url):
            return Invocation(executable: url, arguments: ["--yes", npxPackage] + command, environment: environment)
        }
    }

    static func blocksCommand() -> [String] {
        ["claude", "blocks", "--json", "--active", "--offline"]
    }

    static func dailyCommand(now: Date) -> [String] {
        ["claude", "daily", "--json", "--since", CCUsageParser.sinceArgument(for: now), "--offline"]
    }

    /// Runs both reports. One failing report does not hide the other; both failing throws.
    static func report(using launcher: CCUsageLauncher, home: String = NSHomeDirectory(), configDirectory: String?, now: Date = Date()) async throws -> CCUsageReport {
        var report = CCUsageReport(generatedAt: now)
        var firstError: Error?
        do {
            let data = try await run(invocation(launcher, command: blocksCommand(), home: home, configDirectory: configDirectory))
            report.activeBlock = try CCUsageParser.blocks(from: data).activeBlock
        } catch {
            firstError = error
        }
        do {
            let data = try await run(invocation(launcher, command: dailyCommand(now: now), home: home, configDirectory: configDirectory))
            let today = CCUsageParser.sinceArgument(for: now)
            report.today = try CCUsageParser.daily(from: data).daily.last {
                $0.date.replacingOccurrences(of: "-", with: "") == today
            }
        } catch {
            if report.activeBlock == nil, let firstError { throw firstError }
            if report.activeBlock == nil { throw error }
        }
        return report
    }

    private static func run(_ invocation: Invocation) async throws -> Data {
        let result = try await ProcessRunner.run(invocation.executable, arguments: invocation.arguments, environment: invocation.environment, timeout: timeout)
        guard result.status == 0 else {
            let message = String(decoding: result.stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw CCUsageError.exit(status: result.status, message: String(message.suffix(300)))
        }
        return result.stdout
    }
}
