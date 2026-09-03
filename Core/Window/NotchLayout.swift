import CoreGraphics

/// How the surface sits on the screen: over a real camera housing, or floating below the menu bar.
nonisolated enum NotchStyle: Equatable, Sendable {
    case notch
    case floating
}

/// Everything the SwiftUI layer needs to know about the current screen.
nonisolated struct NotchLayoutMetrics: Equatable, Sendable {
    let screenName: String
    let style: NotchStyle
    /// Size of the housing, or of the floating capsule in its compact state.
    let notchSize: CGSize
    let menuBarHeight: CGFloat
    let panelSize: CGSize

    var hasNotch: Bool { style == .notch }

    /// Used before the first screen measurement.
    static let placeholder = NotchLayoutMetrics(
        screenName: "",
        style: .floating,
        notchSize: NotchLayout.floatingCompactSize,
        menuBarHeight: 24,
        panelSize: NotchLayout.expandedPanelSize
    )

    /// The same screen as if it had no housing; the Debug Preview uses it to exercise the floating style.
    func asFloating() -> NotchLayoutMetrics {
        NotchLayoutMetrics(
            screenName: screenName,
            style: .floating,
            notchSize: NotchLayout.floatingCompactSize,
            menuBarHeight: menuBarHeight,
            panelSize: panelSize
        )
    }
}

/// Sizes and radii of the surface per state. Pure so the Debug Preview and tests share it.
nonisolated enum NotchLayout {
    /// The panel always keeps this footprint; content animates inside it
    /// (window resize animations stutter, content animations do not).
    static let expandedPanelSize = CGSize(width: 600, height: 240)
    /// Compact capsule on screens without a housing.
    static let floatingCompactSize = CGSize(width: 220, height: 36)
    /// Gap between the menu bar and a floating surface.
    static let floatingTopGap: CGFloat = 8
    /// Expanded content area (without the housing on top and without the ears).
    static let expandedContentSize = CGSize(width: 420, height: 150)
    /// Inset between the shape's edge and expanded content.
    static let expandedContentInset: CGFloat = 15
    /// Extra width a popup adds around the housing, and how far it drops below it.
    static let popupExtraWidth: CGFloat = 240
    static let popupExtraHeight: CGFloat = 16
    /// Vertical breathing room of compact content: icon height = housing height − this.
    static let compactContentInset: CGFloat = 12

    struct CornerRadii: Equatable, Sendable {
        let ear: CGFloat
        let bottom: CGFloat
        let top: CGFloat
    }

    static func cornerRadii(for state: NotchState, style: NotchStyle) -> CornerRadii {
        switch style {
        case .notch:
            switch state {
            case .closed: return CornerRadii(ear: 0, bottom: 10, top: 0)
            case .compact: return CornerRadii(ear: 6, bottom: 14, top: 0)
            case .popup: return CornerRadii(ear: 8, bottom: 16, top: 0)
            case .expanded: return CornerRadii(ear: 15, bottom: 20, top: 0)
            }
        case .floating:
            let radius: CGFloat
            switch state {
            case .closed: radius = 0
            case .compact: radius = floatingCompactSize.height / 2
            case .popup: radius = 20
            case .expanded: radius = 20
            }
            return CornerRadii(ear: 0, bottom: radius, top: radius)
        }
    }

    /// Width of one compact wing beside the housing.
    static func compactWingWidth(notchHeight: CGFloat) -> CGFloat {
        max(24, notchHeight - compactContentInset + 10)
    }

    /// Full size of the surface (including the ears) for a state.
    static func shapeSize(for state: NotchState, metrics: NotchLayoutMetrics) -> CGSize {
        let radii = cornerRadii(for: state, style: metrics.style)
        switch metrics.style {
        case .notch:
            let notch = metrics.notchSize
            switch state {
            case .closed:
                return notch
            case .compact:
                let wing = compactWingWidth(notchHeight: notch.height)
                return CGSize(width: notch.width + 2 * wing + 2 * radii.ear, height: notch.height)
            case .popup:
                return CGSize(width: notch.width + popupExtraWidth + 2 * radii.ear, height: notch.height + popupExtraHeight)
            case .expanded:
                return CGSize(width: expandedContentSize.width + 2 * radii.ear, height: notch.height + expandedContentSize.height)
            }
        case .floating:
            switch state {
            case .closed:
                return .zero
            case .compact:
                return floatingCompactSize
            case .popup:
                return CGSize(width: floatingCompactSize.width + 100, height: 48)
            case .expanded:
                return expandedContentSize
            }
        }
    }

    /// Distance from the panel's top edge to the surface.
    static func topInset(for metrics: NotchLayoutMetrics) -> CGFloat {
        metrics.style == .notch ? 0 : metrics.menuBarHeight + floatingTopGap
    }

    /// Where expanded content starts below the surface's top edge.
    static func expandedTopInset(for metrics: NotchLayoutMetrics) -> CGFloat {
        metrics.style == .notch ? metrics.notchSize.height : expandedContentInset
    }

    static func metrics(for geometry: ScreenTopGeometry, screenName: String) -> NotchLayoutMetrics {
        let notchRect = NotchGeometry.notchRect(for: geometry)
        return NotchLayoutMetrics(
            screenName: screenName,
            style: notchRect == nil ? .floating : .notch,
            notchSize: notchRect?.size ?? floatingCompactSize,
            menuBarHeight: geometry.menuBarHeight,
            panelSize: expandedPanelSize
        )
    }

    /// Panel frame centred on the housing (or on the screen when there is none), flush with the screen top.
    static func panelFrame(for geometry: ScreenTopGeometry) -> CGRect {
        let anchorMidX = NotchGeometry.notchRect(for: geometry)?.midX ?? geometry.frame.midX
        return NotchGeometry.panelFrame(
            centeredAt: anchorMidX,
            screenFrame: geometry.frame,
            panelSize: expandedPanelSize
        )
    }
}
