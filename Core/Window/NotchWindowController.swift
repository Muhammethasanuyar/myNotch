import AppKit
import SwiftUI

/// Creates the notch panel, hosts the SwiftUI engine in it and keeps the panel aligned with the
/// notch screen (or the main screen as a fallback) across display changes.
final class NotchWindowController: NSWindowController {
    let model: NotchViewModel
    private let content: NotchContentProvider
    private let hostingView: NotchHostingView<NotchRootView>
    private let debugTint: Bool
    private(set) var metrics: NotchLayoutMetrics = .placeholder
    private var clickOutsideMonitor: Any?

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

    private func reposition() {
        guard let panel = window else {
            assertionFailure("NotchWindowController lost its panel")
            return
        }
        guard let screen = Self.targetScreen() else {
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

    /// Prefers a screen with a notch; falls back to the main screen.
    private static func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.hasNotch } ?? NSScreen.main
    }
}
