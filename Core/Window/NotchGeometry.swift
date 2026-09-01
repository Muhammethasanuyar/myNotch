import AppKit

/// The top-edge geometry AppKit reports for a screen, captured as plain values so the
/// notch math stays pure and testable without an `NSScreen`.
nonisolated struct ScreenTopGeometry: Equatable, Sendable {
    /// Screen frame in global AppKit coordinates (origin bottom-left).
    let frame: CGRect
    /// `NSScreen.safeAreaInsets.top`; zero on screens without a camera housing.
    let safeAreaTop: CGFloat
    /// `NSScreen.auxiliaryTopLeftArea`: usable menu bar area left of the housing.
    let auxiliaryTopLeft: CGRect?
    /// `NSScreen.auxiliaryTopRightArea`: usable menu bar area right of the housing.
    let auxiliaryTopRight: CGRect?
}

/// Pure notch geometry. Never hardcodes dimensions; everything derives from what the screen reports.
nonisolated enum NotchGeometry {
    /// Bounding rectangle of the camera housing in screen coordinates, or `nil` when the screen has no notch.
    static func notchRect(for screen: ScreenTopGeometry) -> CGRect? {
        guard screen.safeAreaTop > 0,
              let left = screen.auxiliaryTopLeft,
              let right = screen.auxiliaryTopRight else {
            return nil
        }
        let width = right.minX - left.maxX
        guard width > 0 else { return nil }
        return CGRect(
            x: left.maxX,
            y: screen.frame.maxY - screen.safeAreaTop,
            width: width,
            height: screen.safeAreaTop
        )
    }

    /// Frame for the always-expanded panel: horizontally centred on `anchorMidX`, top edge flush with the screen top.
    static func panelFrame(centeredAt anchorMidX: CGFloat, screenFrame: CGRect, panelSize: CGSize) -> CGRect {
        CGRect(
            x: anchorMidX - panelSize.width / 2,
            y: screenFrame.maxY - panelSize.height,
            width: panelSize.width,
            height: panelSize.height
        )
    }
}

extension NSScreen {
    /// Snapshot of this screen's top-edge geometry for the pure `NotchGeometry` helpers.
    var topGeometry: ScreenTopGeometry {
        ScreenTopGeometry(
            frame: frame,
            safeAreaTop: safeAreaInsets.top,
            auxiliaryTopLeft: auxiliaryTopLeftArea,
            auxiliaryTopRight: auxiliaryTopRightArea
        )
    }

    var hasNotch: Bool {
        notchFrame != nil
    }

    var notchFrame: CGRect? {
        NotchGeometry.notchRect(for: topGeometry)
    }
}
