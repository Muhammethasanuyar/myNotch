import AppKit
import SwiftUI

/// Creates the notch panel, hosts the SwiftUI engine in it and keeps the panel aligned with the
/// notch screen (or the main screen as a fallback) across display changes.
final class NotchWindowController: NSWindowController {
    let model: NotchViewModel
    private let content: NotchContentProvider
    private let hostingView: NotchHostingView
    private let debugTint: Bool
    private(set) var metrics: NotchLayoutMetrics = .placeholder
    private var clickOutsideMonitor: Any?
    private var dragSessionMonitor: NotchDragSessionMonitor?
    /// Which display to sit on; changing it moves the panel at once.
    var screenPreference: ScreenPreference = .automatic {
        didSet { if screenPreference != oldValue { reposition() } }
    }

    /// - Parameter collapsesOnOutsideClick: normally true; the Debug Preview's forced states turn it off
    ///   so a screenshot session is not undone by an unrelated click.
    init(model: NotchViewModel, content: NotchContentProvider, debugTint: Bool, collapsesOnOutsideClick: Bool = true) {
        self.model = model
        self.content = content
        self.debugTint = debugTint

        let hostingView = NotchHostingView(
            rootView: NotchRootView(model: model, metrics: .placeholder, content: content, debugTint: debugTint)
        )
        // AppKit owns the panel geometry; SwiftUI must not push size constraints onto the window.
        hostingView.sizingOptions = []
        self.hostingView = hostingView

        let panel = NotchPanel(contentRect: CGRect(origin: .zero, size: NotchLayout.expandedPanelSize))
        panel.contentView = hostingView
        super.init(window: panel)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        if collapsesOnOutsideClick {
            installClickOutsideMonitor()
        }
        hostingView.acceptsFileDrops = { [content] in content.dropTargetModuleID() != nil }
        hostingView.onDragTargeting = { [weak self] point in self?.dragTargeting(point) }
        hostingView.onFileDrop = { [weak self] urls, point in self?.fileDropped(urls, at: point) ?? false }
        let dragMonitor = NotchDragSessionMonitor(
            hasTarget: { [content] in content.dropTargetModuleID() != nil },
            onChange: { [weak model] active in model?.isDragSessionActive = active }
        )
        dragMonitor.install()
        dragSessionMonitor = dragMonitor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NotchWindowController does not support NSCoding")
    }

    /// Measures the target screen, positions the panel over the notch and orders it front.
    func show() {
        reposition()
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        reposition()
    }

    /// Global monitors never receive events from our own window, so every click seen here
    /// happened outside the notch and should collapse it.
    private func installClickOutsideMonitor() {
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.collapse()
            }
        }
    }

    // MARK: File drags

    private func dragTargeting(_ point: CGPoint?) {
        guard let moduleID = content.dropTargetModuleID() else { return }
        model.dragTargetingChanged(point != nil, moduleID: moduleID)
        content.dropTargetingChanged(point.flatMap(unitPoint))
    }

    private func fileDropped(_ urls: [URL], at point: CGPoint) -> Bool {
        let accepted = content.acceptDrop(NotchDrop(urls: urls, unitPoint: unitPoint(point)))
        model.dropLanded()
        return accepted
    }

    /// Where over the module's card the point is, when the card is showing.
    private func unitPoint(_ point: CGPoint) -> CGPoint? {
        guard case .expanded(let moduleID) = model.state else { return nil }
        return NotchLayout.expandedContentUnitPoint(
            viewPoint: point,
            metrics: metrics,
            showsBanner: model.banner != nil,
            showsSwitcher: ModuleScreenList.shouldShow(content.screens(moduleID))
        )
    }

    private func reposition() {
        guard let panel = window else {
            assertionFailure("NotchWindowController lost its panel")
            return
        }
        guard let screen = Self.targetScreen(preference: screenPreference) else {
            panel.orderOut(nil)
            return
        }
        let geometry = screen.topGeometry
        metrics = NotchLayout.metrics(for: geometry, screenName: screen.localizedName)
        hostingView.rootView = NotchRootView(model: model, metrics: metrics, content: content, debugTint: debugTint)
        panel.setFrame(NotchLayout.panelFrame(for: geometry), display: true)
        model.graceRect = NotchLayout.graceRect(panelFrame: panel.frame, metrics: metrics)
        panel.orderFrontRegardless()
    }

    /// The preferred screen while it is connected; otherwise the notch screen, then the main one.
    private static func targetScreen(preference: ScreenPreference) -> NSScreen? {
        let screens = NSScreen.screens
        let candidates = screens.map {
            ScreenPreference.Candidate(name: $0.localizedName, hasNotch: $0.hasNotch, isMain: $0 == NSScreen.main)
        }
        guard let chosen = preference.resolve(in: candidates), let index = candidates.firstIndex(of: chosen) else {
            return nil
        }
        return screens[index]
    }
}
