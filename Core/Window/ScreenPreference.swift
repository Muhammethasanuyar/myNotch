import Foundation

/// Which display the notch surface lives on. `automatic` picks the screen with a notch, or the
/// main screen when no built-in display is attached; a named screen is used while it is connected
/// and falls back to automatic the moment it is not.
nonisolated enum ScreenPreference: Hashable, Sendable {
    case automatic
    case named(String)

    /// The word stored for `.automatic`; anything else is a screen name.
    static let automaticValue = "automatic"

    init(storedValue: String?) {
        guard let storedValue, !storedValue.isEmpty, storedValue != Self.automaticValue else {
            self = .automatic
            return
        }
        self = .named(storedValue)
    }

    var storedValue: String {
        switch self {
        case .automatic: Self.automaticValue
        case .named(let name): name
        }
    }

    /// What the resolver needs to know about a screen; `NSScreen` only adapts to it.
    struct Candidate: Equatable, Sendable {
        let name: String
        let hasNotch: Bool
        let isMain: Bool
    }

    /// The candidate the notch should sit on, or `nil` with no screens at all.
    func resolve(in candidates: [Candidate]) -> Candidate? {
        if case .named(let name) = self, let match = candidates.first(where: { $0.name == name }) {
            return match
        }
        return candidates.first(where: \.hasNotch)
            ?? candidates.first(where: \.isMain)
            ?? candidates.first
    }
}
