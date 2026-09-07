import Foundation

/// Finds the user's `gh` command line tool. An app launched from the Finder has only the system
/// directories on its PATH, so the usual install locations are checked explicitly.
nonisolated enum GHLocator {
    /// UserDefaults key for an explicit path (Settings → Builds).
    static let pathOverrideKey = "ciGHPath"

    static func candidateDirectories(home: String) -> [String] {
        ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", "/usr/bin"]
    }

    static func locate(
        home: String = NSHomeDirectory(),
        override: String? = UserDefaults.standard.string(forKey: pathOverrideKey),
        directories: [String]? = nil,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> URL? {
        if let override = override?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            return isExecutable(override) ? URL(fileURLWithPath: override) : nil
        }
        for directory in directories ?? candidateDirectories(home: home) {
            let path = directory + "/gh"
            if isExecutable(path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }
}
