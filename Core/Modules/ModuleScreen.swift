import Foundation

/// How a module appears in the expanded card's screen switcher — the strip that says which screen
/// is showing and moves to another one without closing the notch.
///
/// A screen speaks for an app whenever it has one (`appBundleIdentifier`), so the strip doubles as
/// "what is live on this Mac right now": Spotify's own icon while Spotify runs, and nothing while
/// it does not.
nonisolated struct ModuleScreen: Identifiable, Equatable, Sendable {
    /// Unique across every module. A module with one screen uses its own id; one with several
    /// (the media module has a screen per running player) derives an id per screen.
    let id: String
    /// The module that owns the screen and knows what to do when it is picked.
    let moduleID: String
    /// Name of the screen. It may follow what the module is doing — "Spotify" rather than "Media".
    let title: String
    /// SF Symbol used when there is no app icon to borrow.
    let symbolName: String
    /// Bundle id of the app this screen speaks for, when it has one.
    let appBundleIdentifier: String?
    /// Whether the module has something to show right now. An unavailable screen is left out.
    let isAvailable: Bool

    init(id: String, moduleID: String, title: String, symbolName: String, appBundleIdentifier: String? = nil, isAvailable: Bool = true) {
        self.id = id
        self.moduleID = moduleID
        self.title = title
        self.symbolName = symbolName
        self.appBundleIdentifier = appBundleIdentifier
        self.isAvailable = isAvailable
    }
}

nonisolated enum ModuleScreenList {
    /// The screens the switcher offers, keeping registration order so the icons never jump: the
    /// ones with something to show, plus whichever is on screen — a card must not lose its own tab
    /// because its app went quiet while the user was reading it.
    static func visible(_ screens: [ModuleScreen], activeID: String?) -> [ModuleScreen] {
        // `activeID` is a screen id, not a module id: a module with several screens shows one.

        screens.filter { $0.isAvailable || $0.id == activeID }
    }

    /// One screen needs no switcher: the card already is that screen.
    static func shouldShow(_ screens: [ModuleScreen]) -> Bool {
        screens.count > 1
    }
}
