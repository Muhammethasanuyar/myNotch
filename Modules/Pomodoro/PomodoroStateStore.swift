import Foundation

/// Where the running cycle survives a relaunch. Working state, not a preference, so it has its own
/// key rather than a `SettingsKey` — the same reasoning as `ModuleManager.preferredModuleKey`.
nonisolated struct PomodoroStateStore {
    static let key = "pomodoroState"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PomodoroSnapshot? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        do {
            return try JSONDecoder().decode(PomodoroSnapshot.self, from: data)
        } catch {
            assertionFailure("Unreadable pomodoro state: \(error)")
            return nil
        }
    }

    func save(_ snapshot: PomodoroSnapshot) {
        if snapshot.phase == .idle {
            defaults.removeObject(forKey: Self.key)
            return
        }
        do {
            defaults.set(try JSONEncoder().encode(snapshot), forKey: Self.key)
        } catch {
            assertionFailure("Unencodable pomodoro state: \(error)")
        }
    }
}
