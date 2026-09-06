import AppKit

/// Notices a file drag anywhere on screen without polling and without watching the cursor: a
/// global mouse monitor only receives events while a button is held, and the drag pasteboard's
/// change count moves the moment a drag session begins. Moving a window or selecting text never
/// touches that pasteboard, so only real drags count. Nothing here needs the Accessibility permission.
@MainActor
final class NotchDragSessionMonitor {
    private let hasTarget: () -> Bool
    private let onChange: (Bool) -> Void
    private var monitor: Any?
    private var changeCountAtMouseDown = 0
    private(set) var isActive = false

    /// - Parameters:
    ///   - hasTarget: whether any module would take a drop right now; checked as a drag begins.
    ///   - onChange: a drag session started (`true`) or the button was released (`false`).
    init(hasTarget: @escaping () -> Bool, onChange: @escaping (Bool) -> Void) {
        self.hasTarget = hasTarget
        self.onChange = onChange
    }

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(type: event.type)
            }
        }
    }

    func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        set(false)
    }

    /// Pure enough to test: the pasteboard's count is read here so the decision stays in one place.
    func handle(type: NSEvent.EventType, dragChangeCount: Int = NSPasteboard(name: .drag).changeCount) {
        switch type {
        case .leftMouseDown:
            changeCountAtMouseDown = dragChangeCount
        case .leftMouseDragged:
            guard !isActive, dragChangeCount != changeCountAtMouseDown, hasTarget() else { return }
            set(true)
        case .leftMouseUp:
            set(false)
        default:
            break
        }
    }

    private func set(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        onChange(active)
    }
}
