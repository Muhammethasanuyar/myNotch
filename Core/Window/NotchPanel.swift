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

/// Hosting view for the notch content, and the panel's drag destination.
///
/// `acceptsFirstMouse` matters here: the panel never becomes key, so without it AppKit would eat
/// the first click as an activation click and a transport button would need to be pressed twice
/// whenever another app is in front.
///
/// File drags are taken in AppKit rather than with SwiftUI's `onDrop`: the surface is empty while
/// the notch is closed, so there would be no SwiftUI view to drop on, and the module that takes the
/// files is not rendered until the drag has opened it. The window server decides which window a
/// drag reaches by pixel alpha, exactly as for clicks, so the housing catches drags on its own and
/// `NotchDropDetector` widens the target during a drag.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    /// Whether any module takes file drops right now; read as a drag arrives.
    var acceptsFileDrops: () -> Bool = { false }
    /// A file drag is over the panel at this point (view coordinates, top-left origin), or left (`nil`).
    var onDragTargeting: (CGPoint?) -> Void = { _ in }
    /// Files were dropped at the point; returns whether a module took them.
    var onFileDrop: ([URL], CGPoint) -> Bool = { _, _ in false }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NotchHostingView does not support NSCoding")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard acceptsFileDrops(), Self.carriesFileURLs(sender) else { return [] }
        onDragTargeting(convert(sender.draggingLocation, from: nil))
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onDragTargeting(nil)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = Self.fileURLs(sender)
        guard !urls.isEmpty else { return false }
        return onFileDrop(urls, convert(sender.draggingLocation, from: nil))
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        onDragTargeting(nil)
    }

    private static var fileURLOptions: [NSPasteboard.ReadingOptionKey: Any] { [.urlReadingFileURLsOnly: true] }

    private static func carriesFileURLs(_ sender: any NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: fileURLOptions)
    }

    private static func fileURLs(_ sender: any NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: fileURLOptions) as? [URL]) ?? []
    }
}
