import SwiftUI

/// The views the engine renders inside the surface. Phase 2's ModuleManager supplies the real
/// provider from the active module; until then the Debug Preview's fake content is used.
///
/// Every closure receives the morph namespace so shared elements (an artwork that travels from
/// the compact wing into the expanded card) can use `matchedGeometryEffect`.
struct NotchContentProvider {
    var compactLeading: @MainActor (Namespace.ID) -> AnyView
    var compactTrailing: @MainActor (Namespace.ID) -> AnyView
    var expanded: @MainActor (_ moduleID: String, Namespace.ID) -> AnyView
    var popup: @MainActor (NotchEvent, Namespace.ID) -> AnyView
    /// The screens the expanded card can switch between; the engine draws the switcher itself.
    var screens: @MainActor (_ activeModuleID: String) -> [ModuleScreen] = { _ in [] }
    /// Which screen of the expanded module is showing — a module can own more than one.
    var activeScreenID: @MainActor (_ activeModuleID: String) -> String = { $0 }
    /// The user picked a screen; the manager focuses it and puts its module on the card.
    var selectScreen: @MainActor (ModuleScreen) -> Void = { _ in }

    static var empty: NotchContentProvider {
        NotchContentProvider(
            compactLeading: { _ in AnyView(EmptyView()) },
            compactTrailing: { _ in AnyView(EmptyView()) },
            expanded: { _, _ in AnyView(EmptyView()) },
            popup: { _, _ in AnyView(EmptyView()) }
        )
    }
}
