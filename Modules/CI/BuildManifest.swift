import Foundation

/// `~/Library/Developer/Xcode/DerivedData/<project>/Logs/Build/LogStoreManifest.plist`: Xcode's own
/// index of build logs. Undocumented, so every field is optional and decoded by hand; verified on
/// Xcode 26.4 (`logFormatVersion` 12) with `highLevelStatus` S/W/E and CFAbsoluteTime stamps.
nonisolated struct BuildLogManifest: Decodable, Sendable {
    let logFormatVersion: Int?
    let logs: [String: BuildLogEntry]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        logFormatVersion = try? c.decodeIfPresent(Int.self, forKey: .logFormatVersion)
        logs = (try? c.decodeIfPresent([String: BuildLogEntry].self, forKey: .logs)) ?? [:]
    }

    private enum CodingKeys: String, CodingKey { case logFormatVersion, logs }

    static func decode(_ data: Data) throws -> BuildLogManifest {
        try PropertyListDecoder().decode(BuildLogManifest.self, from: data)
    }

    /// The entries as runs, named after the project folder the manifest lives in.
    func runs(project: String) -> [CIRun] {
        logs.compactMap { id, entry in entry.run(id: id, project: project) }
    }
}

nonisolated struct BuildLogEntry: Decodable, Sendable {
    let uniqueIdentifier: String?
    let title: String?
    let schemeName: String?
    let containerName: String?
    let timeStartedRecording: Double?
    let timeStoppedRecording: Double?
    let primaryObservable: PrimaryObservable?

    struct PrimaryObservable: Decodable, Sendable {
        let highLevelStatus: String?
        let totalNumberOfErrors: Int?
        let totalNumberOfWarnings: Int?
        let totalNumberOfTestFailures: Int?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            highLevelStatus = try? c.decodeIfPresent(String.self, forKey: .highLevelStatus)
            totalNumberOfErrors = try? c.decodeIfPresent(Int.self, forKey: .totalNumberOfErrors)
            totalNumberOfWarnings = try? c.decodeIfPresent(Int.self, forKey: .totalNumberOfWarnings)
            totalNumberOfTestFailures = try? c.decodeIfPresent(Int.self, forKey: .totalNumberOfTestFailures)
        }

        private enum CodingKeys: String, CodingKey { case highLevelStatus, totalNumberOfErrors, totalNumberOfWarnings, totalNumberOfTestFailures }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uniqueIdentifier = try? c.decodeIfPresent(String.self, forKey: .uniqueIdentifier)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        schemeName = try? c.decodeIfPresent(String.self, forKey: .schemeName)
        containerName = try? c.decodeIfPresent(String.self, forKey: .containerName)
        timeStartedRecording = try? c.decodeIfPresent(Double.self, forKey: .timeStartedRecording)
        timeStoppedRecording = try? c.decodeIfPresent(Double.self, forKey: .timeStoppedRecording)
        primaryObservable = try? c.decodeIfPresent(PrimaryObservable.self, forKey: .primaryObservable)
    }

    private enum CodingKeys: String, CodingKey {
        case uniqueIdentifier, title, timeStartedRecording, timeStoppedRecording, primaryObservable
        case schemeName = "schemeIdentifier-schemeName"
        case containerName = "schemeIdentifier-containerName"
    }

    /// A finished build; an entry still recording (no stop time) is a run in progress.
    func run(id: String, project: String) -> CIRun? {
        let errors = primaryObservable?.totalNumberOfErrors ?? 0
        let warnings = primaryObservable?.totalNumberOfWarnings ?? 0
        let testFailures = primaryObservable?.totalNumberOfTestFailures ?? 0
        let finished = CIRules.date(fromRecordingTime: timeStoppedRecording)
        let status: CIStatus = finished == nil
            ? .running
            : CIRules.status(highLevelStatus: primaryObservable?.highLevelStatus, errors: errors + testFailures, warnings: warnings)
        return CIRun(
            id: "xcode:\(uniqueIdentifier ?? id)",
            source: .xcode(project: project),
            title: schemeName ?? title ?? project,
            subtitle: containerName ?? title,
            status: status,
            finishedAt: finished,
            url: nil,
            errorCount: errors + testFailures,
            warningCount: warnings
        )
    }
}
