import AppKit
import SwiftUI

/// Transparent, always-on-top, non-activating panel that sits over the physical notch.
/// The panel keeps the expanded footprint at all times; the SwiftUI content decides what is visible.
final class NotchPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        // `ignoresMouseEvents` is deliberately never set: the window server then passes clicks
        // through transparent pixels on its own, so only the drawn shape catches the cursor.
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// AppKit would otherwise nudge a window down to keep it below the menu bar; the notch lives at the edge.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Hosting view for the notch content.
///
/// `acceptsFirstMouse` matters here: the panel never becomes key, so without it AppKit would eat
/// the first click as an activation click and a transport button would need to be pressed twice
/// whenever another app is in front.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
