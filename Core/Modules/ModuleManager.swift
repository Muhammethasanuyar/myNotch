import SwiftUI

/// Owns the registered modules, decides which one currently has the notch and turns their
/// announcements into notch states.
///
/// Modules never touch `NotchViewModel`: they post on the `EventBus`, the manager resolves
/// priorities (`ModuleResolver`) and drives the view model from one place.
@MainActor
@Observable
final class ModuleManager {
    private(set) var modules: [any NotchModule] = []
    /// The module that currently owns compact content, or `nil` when everyone is idle.
    private(set) var activeModuleID: String?

    /// The module the user last opened on purpose. Hovering reopens it instead of whichever module
    /// owns the compact strip, and it is kept across launches.
    private(set) var preferredModuleID: String?

    let bus: EventBus
    private let model: NotchViewModel
    private let defaults: UserDefaults
    @ObservationIgnored private var subscription: EventBus.Subscription?

    static let preferredModuleKey = "preferredModuleID"

    init(model: NotchViewModel, bus: EventBus = EventBus(), defaults: UserDefaults = .standard) {
        self.model = model
        self.bus = bus
        self.defaults = defaults
        preferredModuleID = defaults.string(forKey: Self.preferredModuleKey)
        subscription = bus.subscribe { [weak self] message in
            self?.handle(message)
        }
    }

    // MARK: Registration

    func register(_ module: any NotchModule) {
        guard !modules.contains(where: { $0.id == module.id }) else {
            assertionFailure("Duplicate module id: \(module.id)")
            return
        }
        modules.append(module)
        if module.isEnabled {
            module.start(context: context(for: module))
        }
        resolveActiveModule()
    }

    /// What a module is handed: the bus, and a way to pass files on to the drop-taking module.
    private func context(for module: any NotchModule) -> ModuleContext {
        ModuleContext(
            moduleID: module.id,
            bus: bus,
            offer: { [weak self] caller, urls in
                self?.dropTarget(excluding: caller)?.acceptDrop(NotchDrop(urls: urls, unitPoint: nil)) ?? false
            },
            canOffer: { [weak self] caller in
                self?.dropTarget(excluding: caller) != nil
            }
        )
    }

    func module(id: String) -> (any NotchModule)? {
        modules.first { $0.id == id }
    }

    /// The app is quitting: every running module lets go of what it holds (child processes,
    /// system observers). The enabled flags stay as they are for the next launch.
    func stopAll() {
        modules.filter(\.isEnabled).forEach { $0.stop() }
    }

    /// Settings toggle: starts or stops the module and re-resolves the notch owner.
    func setEnabled(_ enabled: Bool, for moduleID: String) {
        guard let module = module(id: moduleID), module.isEnabled != enabled else { return }
        module.isEnabled = enabled
        if enabled {
            module.start(context: context(for: module))
        } else {
            module.stop()
            if case .expanded(let expandedID) = model.state, expandedID == moduleID {
                model.collapse()
            }
        }
        resolveActiveModule()
    }

    /// The switcher's entries: every screen of every enabled module that has something to show,
    /// plus the one on the card.
    func screens(activeScreenID: String?) -> [ModuleScreen] {
        ModuleScreenList.visible(modules.filter(\.isEnabled).flatMap(\.screens), activeID: activeScreenID)
    }

    /// The screen the expanded card is showing: the module itself says which of its screens that is.
    func activeScreenID(forModule moduleID: String) -> String {
        module(id: moduleID)?.activeScreenID ?? moduleID
    }

    /// The user picked a screen: focus it inside its module, put that module on the card, and
    /// remember the choice so the next hover lands there too.
    func selectScreen(_ screen: ModuleScreen) {
        guard let module = module(id: screen.moduleID), module.isEnabled else { return }
        module.selectScreen(screen.id)
        preferredModuleID = module.id
        defaults.set(module.id, forKey: Self.preferredModuleKey)
        model.defaultModuleID = module.id
        model.expand(moduleID: module.id)
    }

    /// The enabled module that takes file drops, if any; the first registered wins.
    var dropTargetModule: (any NotchModule)? {
        modules.first { $0.isEnabled && $0.acceptsDrops }
    }

    /// The drop-taking module another module can hand files to — never itself.
    func dropTarget(excluding moduleID: String) -> (any NotchModule)? {
        modules.first { $0.isEnabled && $0.acceptsDrops && $0.id != moduleID }
    }

    var snapshots: [ModuleSnapshot] {
        modules.map {
            ModuleSnapshot(id: $0.id, priority: $0.priority, activity: $0.activity, isEnabled: $0.isEnabled)
        }
    }

    // MARK: Content

    /// The views the notch engine renders.
    /// - Parameter previewFallback: when no module is live, fall back to the first enabled module
    ///   so the Debug Preview can still exercise every state.
    func contentProvider(previewFallback: Bool = false) -> NotchContentProvider {
        NotchContentProvider(
            compactLeading: { [weak self] namespace in
                guard let module = self?.contentModule(previewFallback: previewFallback) else { return AnyView(EmptyView()) }
                return module.compactLeading(namespace: namespace)
            },
            compactTrailing: { [weak self] namespace in
                guard let module = self?.contentModule(previewFallback: previewFallback) else { return AnyView(EmptyView()) }
                return module.compactTrailing(namespace: namespace)
            },
            expanded: { [weak self] moduleID, namespace in
                guard let self else { return AnyView(EmptyView()) }
                let module = self.module(id: moduleID) ?? self.contentModule(previewFallback: previewFallback)
                return module?.expandedView(namespace: namespace) ?? AnyView(EmptyView())
            },
            popup: { [weak self] event, namespace in
                if let custom = self?.module(id: event.moduleID)?.popupView(for: event, namespace: namespace) {
                    return custom
                }
                return AnyView(NotchEventRow(event: event))
            },
            // Read while the card renders, so the strip follows what is running.
            screens: { [weak self] activeModuleID in
                guard let self else { return [] }
                return screens(activeScreenID: activeScreenID(forModule: activeModuleID))
            },
            activeScreenID: { [weak self] activeModuleID in
                self?.activeScreenID(forModule: activeModuleID) ?? activeModuleID
            },
            selectScreen: { [weak self] screen in
                self?.selectScreen(screen)
            },
            dropTargetModuleID: { [weak self] in
                self?.dropTargetModule?.id
            },
            dropTargetingChanged: { [weak self] unitPoint in
                self?.dropTargetModule?.dropTargetingChanged(unitPoint)
            },
            acceptDrop: { [weak self] drop in
                self?.dropTargetModule?.acceptDrop(drop) ?? false
            }
        )
    }

    private func contentModule(previewFallback: Bool) -> (any NotchModule)? {
        if let activeModuleID, let module = module(id: activeModuleID) {
            return module
        }
        return previewFallback ? modules.first(where: \.isEnabled) : nil
    }

    // MARK: Event handling

    private func handle(_ message: EventBus.Message) {
        switch message {
        case .activityChanged:
            resolveActiveModule()
        case .popup(let event):
            guard ModuleResolver.acceptsPopup(from: event.moduleID, snapshots: snapshots) else { return }
            resolveActiveModule()
            model.showPopup(event)
        }
    }

    private func resolveActiveModule() {
        let winner = ModuleResolver.resolve(snapshots)
        activeModuleID = winner?.id
        // Hovering opens the screen the user last chose while it can still be shown; failing that,
        // whoever owns the notch, and with nobody live the first enabled module.
        let enabled = modules.filter(\.isEnabled)
        model.defaultModuleID = ModuleResolver.expandedDestination(
            preferred: preferredModuleID,
            winnerID: winner?.id,
            screens: enabled.flatMap(\.screens),
            enabledIDs: enabled.map(\.id)
        ) ?? "none"
        model.setLiveContent(winner != nil)
    }
}

/// Generic popup body for modules that do not provide their own: the event's symbol and one line.
struct NotchEventRow: View {
    let event: NotchEvent

    var body: some View {
        NotchPopupLine(title: event.title, detail: event.detail, symbolName: event.symbolName ?? "bell.fill")
    }
}

/// The one-line popup text every module shares: bold title, dimmed detail, centred in the strip
/// under the housing (or in the banner capsule inside an expanded card), never more than a line.
struct NotchPopupLine: View {
    let title: String
    var detail: String?
    var symbolName: String?

    var body: some View {
        HStack(spacing: 6) {
            if let symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: 12, weight: .semibold))
            }
            text
        }
        .font(.system(size: 13))
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
    }

    private var text: Text {
        let titleText = Text(title).fontWeight(.semibold)
        guard let detail, !detail.isEmpty else { return titleText }
        return titleText + Text(" — \(detail)").foregroundStyle(.white.opacity(0.6))
    }
}
