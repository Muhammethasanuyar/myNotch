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
    static let expandedPanelSize = CGSize(width: 600, height: 280)
    /// Compact capsule on screens without a housing.
    static let floatingCompactSize = CGSize(width: 220, height: 36)
    /// Gap between the menu bar and a floating surface.
    static let floatingTopGap: CGFloat = 8
    /// Expanded content area (without the housing on top and without the ears).
    static let expandedContentSize = CGSize(width: 420, height: 150)
    /// Inset between the shape's edge and expanded content.
    static let expandedContentInset: CGFloat = 15
    /// Gap between the bottom of the housing and expanded content. Strokes and shadows bleed a few
    /// points past their frames, and the housing's corners are rounded; without this a ring drawn
    /// flush against the housing reads as tucked underneath it.
    static let expandedTopGap: CGFloat = 8
    /// Extra width a popup adds around the housing, and how far it drops below it.
    static let popupExtraWidth: CGFloat = 240
    static let popupExtraHeight: CGFloat = 16
    /// Vertical breathing room of compact content: icon height = housing height − this.
    static let compactContentInset: CGFloat = 12
    /// Strip reserved above expanded content while another module's banner is showing, so the two
    /// never overlap.
    static let bannerHeight: CGFloat = 28
    /// Strip along the bottom of the expanded card that names the current screen and switches
    /// between them.
    static let switcherHeight: CGFloat = 26
    /// How far beyond the expanded surface the cursor may wander and still count as on it.
    static let graceMargin = CGSize(width: 32, height: 28)

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
    /// - Parameters:
    ///   - showsBanner: another module is announcing something inside the expanded surface, which
    ///     needs a strip of its own.
    ///   - showsSwitcher: the expanded card offers more than one screen, so it carries the switcher.
    static func shapeSize(for state: NotchState, metrics: NotchLayoutMetrics, showsBanner: Bool = false, showsSwitcher: Bool = false) -> CGSize {
        let base = baseShapeSize(for: state, metrics: metrics)
        guard state.isExpanded else { return base }
        let extra = (showsBanner ? bannerHeight : 0) + (showsSwitcher ? switcherHeight : 0)
        return CGSize(width: base.width, height: base.height + extra)
    }

    private static func baseShapeSize(for state: NotchState, metrics: NotchLayoutMetrics) -> CGSize {
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
                return CGSize(width: expandedContentSize.width + 2 * radii.ear, height: notch.height + expandedTopGap + expandedContentSize.height)
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

    /// Where expanded content starts below the surface's top edge: under the housing plus a gap.
    static func expandedTopInset(for metrics: NotchLayoutMetrics) -> CGFloat {
        metrics.style == .notch ? metrics.notchSize.height + expandedTopGap : expandedContentInset
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

    /// Screen-space zone around the expanded surface within which the cursor still counts as
    /// hovering. The surface hangs centred from the panel's top edge; the zone reaches up to the
    /// screen edge (the housing sits there) and `graceMargin` beyond the surface on every side.
    ///
    /// Measured against the tallest the card can get (banner and switcher included), because the
    /// zone is computed once per screen change rather than per state.
    static func graceRect(panelFrame: CGRect, metrics: NotchLayoutMetrics) -> CGRect {
        let size = shapeSize(for: .expanded(moduleID: ""), metrics: metrics, showsBanner: true, showsSwitcher: true)
        let top = topInset(for: metrics)
        let surface = CGRect(
            x: panelFrame.midX - size.width / 2,
            y: panelFrame.maxY - top - size.height,
            width: size.width,
            height: size.height + top
        )
        return surface.insetBy(dx: -graceMargin.width, dy: -graceMargin.height)
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
