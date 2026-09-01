import AppKit
import SwiftUI

/// Creates the notch panel, hosts the SwiftUI root view in it and keeps the panel aligned
/// with the notch screen (or the main screen as a fallback) across display changes.
final class NotchWindowController: NSWindowController {
    private let hostingView: NSHostingView<NotchRootView>
    private let debugTint: Bool
    private(set) var metrics: NotchLayoutMetrics = .placeholder

    init(debugTint: Bool) {
        self.debugTint = debugTint

        let hostingView = NSHostingView(rootView: NotchRootView(metrics: .placeholder, debugTint: debugTint))
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
        hostingView.rootView = NotchRootView(metrics: metrics, debugTint: debugTint)
        panel.setFrame(NotchLayout.panelFrame(for: geometry), display: true)
        panel.orderFrontRegardless()
    }

    /// Prefers a screen with a notch; falls back to the main screen.
    private static func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.hasNotch } ?? NSScreen.main
    }
}
