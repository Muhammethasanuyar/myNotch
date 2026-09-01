import CoreGraphics

/// Phase 0 layout constants and the derived per-screen metrics.
/// Phase 1 moves the shape parameters into `NotchShape` / `Anim`.
nonisolated enum NotchLayout {
    /// The panel always keeps the expanded footprint; content animates inside it
    /// (window resize animations stutter, content animations do not).
    static let expandedPanelSize = CGSize(width: 600, height: 240)
    /// Placeholder "closed" size for screens without a notch. Floating capsule mode arrives in Phase 1.
    static let fallbackNotchSize = CGSize(width: 200, height: 32)
    /// Bottom corner radius of the closed shape, matching the housing's rounded corners.
    static let closedCornerRadius: CGFloat = 10

    static func metrics(for geometry: ScreenTopGeometry, screenName: String) -> NotchLayoutMetrics {
        let notchRect = NotchGeometry.notchRect(for: geometry)
        return NotchLayoutMetrics(
            screenName: screenName,
            hasNotch: notchRect != nil,
            notchSize: notchRect?.size ?? fallbackNotchSize,
            panelSize: expandedPanelSize
        )
    }

    /// Panel frame centred on the notch (or on the screen when there is none), flush with the screen top.
    static func panelFrame(for geometry: ScreenTopGeometry) -> CGRect {
        let anchorMidX = NotchGeometry.notchRect(for: geometry)?.midX ?? geometry.frame.midX
        return NotchGeometry.panelFrame(
            centeredAt: anchorMidX,
            screenFrame: geometry.frame,
            panelSize: expandedPanelSize
        )
    }
}

/// Everything the SwiftUI layer needs to know about the current screen.
nonisolated struct NotchLayoutMetrics: Equatable, Sendable {
    let screenName: String
    let hasNotch: Bool
    let notchSize: CGSize
    let panelSize: CGSize

    /// Used before the first screen measurement.
    static let placeholder = NotchLayoutMetrics(
        screenName: "",
        hasNotch: false,
        notchSize: NotchLayout.fallbackNotchSize,
        panelSize: NotchLayout.expandedPanelSize
    )
}
