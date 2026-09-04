import Foundation
import Security

// Adapted from https://github.com/ericjypark/codex-island (MIT): the env → Keychain → file order,
// Keychain discovery without `kSecReturnData`, and reading the secret through `/usr/bin/security`
// so the ACL prompt is never shown. Restructured into a pure, testable enum.

/// Claude Code's own sign-in, read but never written: Anthropic revokes the whole token family when
/// a stale refresh token is reused, so a second refresher would break the user's CLI session.
nonisolated struct ClaudeCredential: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case environment
        case keychain(service: String)
        case file(URL)
    }

    let accessToken: String
    let expiresAt: Date?
    /// "pro", "max", … — the endpoint does not report the plan, only the credential does.
    let subscriptionType: String?
    let source: Source

    /// Treated as expired a minute early so a request never races the expiry.
    func isExpired(at now: Date = Date(), tolerance: TimeInterval = 60) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt.addingTimeInterval(-tolerance)
    }
}

nonisolated enum ClaudeCredentials {
    static let environmentKey = "CLAUDE_CODE_OAUTH_TOKEN"
    static let configDirectoryKey = "CLAUDE_CONFIG_DIR"
    static let keychainService = "Claude Code-credentials"

    /// `CLAUDE_CODE_OAUTH_TOKEN` (what Claude Desktop injects) → Keychain (what Claude Code 2.x keeps
    /// current) → `.credentials.json` (the fallback the CLI itself uses when the Keychain is
    /// unavailable, often a stale leftover).
    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment,
                        configDirectory: String? = nil,
                        home: String = NSHomeDirectory()) async -> ClaudeCredential? {
        if let token = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            return ClaudeCredential(accessToken: token, expiresAt: nil, subscriptionType: nil, source: .environment)
        }
        for item in keychainItems() {
            if let blob = await readKeychainSecret(service: item.service, account: item.account),
               let credential = credential(fromBlob: blob, source: .keychain(service: item.service)) {
                return credential
            }
        }
        let file = credentialsFileURL(configDirectory: configDirectory ?? environment[configDirectoryKey], home: home)
        if let data = try? Data(contentsOf: file), let credential = credential(fromBlob: data, source: .file(file)) {
            return credential
        }
        return nil
    }

    // MARK: Keychain

    struct KeychainItem: Equatable, Sendable {
        let service: String
        let account: String
        let modified: Date?
    }

    /// Metadata-only query (`kSecReturnAttributes` without `kSecReturnData`): it never triggers the
    /// keychain ACL prompt. Bare services sort before the per-config-dir `-<hash>` variants.
    static func keychainItems() -> [KeychainItem] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecReturnAttributes: true
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let attributes = result as? [[CFString: Any]] else { return [] }
        return attributes.compactMap { item -> KeychainItem? in
            guard let service = item[kSecAttrService] as? String, isClaudeCredentialService(service) else { return nil }
            return KeychainItem(
                service: service,
                account: item[kSecAttrAccount] as? String ?? "",
                modified: item[kSecAttrModificationDate] as? Date
            )
        }
        .sorted { ($0.service.count, $0.service) < ($1.service.count, $1.service) }
    }

    /// `Claude Code-credentials` itself or a `Claude Code-credentials-<hash>` variant, but not
    /// siblings like `Claude Code-doctor-probe`.
    static func isClaudeCredentialService(_ service: String) -> Bool {
        service == keychainService || service.hasPrefix(keychainService + "-")
    }

    /// Reads one item's secret with `/usr/bin/security`. Claude Code rewrites the item on every
    /// token rotation, which resets its partition list and wipes any "Always Allow" the user gave
    /// us; the `security` binary sits in the `apple-tool:` partition, so its reads stay silent.
    static func readKeychainSecret(service: String, account: String) async -> Data? {
        guard let result = try? await ProcessRunner.run(
            URL(fileURLWithPath: "/usr/bin/security"),
            arguments: securityArguments(service: service, account: account),
            timeout: 10
        ), result.status == 0 else { return nil }
        return result.stdout
    }

    static func securityArguments(service: String, account: String) -> [String] {
        var arguments = ["find-generic-password", "-s", service]
        if !account.isEmpty { arguments += ["-a", account] }
        arguments.append("-w")
        return arguments
    }

    // MARK: File store

    /// `$CLAUDE_CONFIG_DIR/.credentials.json` (first entry of a comma-separated list), else `~/.claude/.credentials.json`.
    static func credentialsFileURL(configDirectory: String?, home: String) -> URL {
        let first = configDirectory?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        let directory = ClaudePaths.expandTilde(first ?? home + "/.claude", home: home)
        return URL(fileURLWithPath: directory).appendingPathComponent(".credentials.json")
    }

    // MARK: Blob decoding

    /// `security -w` prints the secret as hex when it contains bytes it cannot show; otherwise as is.
    static func decodeBlob(_ raw: Data) -> [String: Any]? {
        guard let text = String(data: raw, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] {
            return object
        }
        guard text.count.isMultiple(of: 2), text.allSatisfy(\.isHexDigit), let bytes = hexData(text) else { return nil }
        return try? JSONSerialization.jsonObject(with: bytes) as? [String: Any]
    }

    private static func hexData(_ hex: String) -> Data? {
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    /// `claudeAiOauth.accessToken` plus `expiresAt` (epoch **milliseconds**) and the plan.
    static func credential(fromBlob raw: Data, source: ClaudeCredential.Source) -> ClaudeCredential? {
        guard let blob = decodeBlob(raw),
              let oauth = blob["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        let expiresAt = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return ClaudeCredential(
            accessToken: token,
            expiresAt: expiresAt,
            subscriptionType: oauth["subscriptionType"] as? String,
            source: source
        )
    }

    // MARK: Change detection

    /// Newest modification across the stores, from metadata only. Cheap enough to poll every few
    /// seconds while waiting for the user to sign in, without touching the secret.
    static func storeFingerprint(configDirectory: String? = ProcessInfo.processInfo.environment[configDirectoryKey],
                                 home: String = NSHomeDirectory()) -> Date? {
        let keychain = keychainItems().compactMap(\.modified).max()
        let file = credentialsFileURL(configDirectory: configDirectory, home: home)
        let fileDate = (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]) as? Date
        return [keychain, fileDate].compactMap { $0 }.max()
    }
}
