import AppKit
import SwiftUI

/// Regular, resizable window that renders the notch content for fast visual iteration
/// without deploying to the real notch.
final class DebugPreviewWindowController: NSWindowController {
    private let hostingView: NSHostingView<DebugPreviewView>

    private let liveModel: NotchViewModel
    private let manager: ModuleManager

    init(metrics: NotchLayoutMetrics, liveModel: NotchViewModel, manager: ModuleManager) {
        self.liveModel = liveModel
        self.manager = manager
        let hostingView = NSHostingView(rootView: DebugPreviewView(metrics: metrics, liveModel: liveModel, manager: manager))
        self.hostingView = hostingView

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 780, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MyNotch — Debug Preview"
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("DebugPreviewWindowController does not support NSCoding")
    }

    /// Refreshes the preview with the latest metrics and brings the window forward.
    func show(metrics: NotchLayoutMetrics) {
        hostingView.rootView = DebugPreviewView(metrics: metrics, liveModel: liveModel, manager: manager)
        NSApplication.shared.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
