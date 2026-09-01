import AppKit
import SwiftUI

/// Regular, resizable window that renders the notch content for fast visual iteration
/// without deploying to the real notch.
final class DebugPreviewWindowController: NSWindowController {
    private let hostingView: NSHostingView<DebugPreviewView>

    init(metrics: NotchLayoutMetrics) {
        let hostingView = NSHostingView(rootView: DebugPreviewView(metrics: metrics))
        self.hostingView = hostingView

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 760, height: 440),
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
        hostingView.rootView = DebugPreviewView(metrics: metrics)
        NSApplication.shared.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
