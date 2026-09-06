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
    static let expandedContentSize = CGSize(width: 480, height: 150)
    /// Inset between the shape's edge and expanded content.
    static let expandedContentInset: CGFloat = 15
    /// Gap between the bottom of the housing and expanded content. Strokes and shadows bleed a few
    /// points past their frames, and the housing's corners are rounded; without this a ring drawn
    /// flush against the housing reads as tucked underneath it.
    static let expandedTopGap: CGFloat = 8
    /// Extra width a popup adds around the housing, and the text strip it hangs below the compact
    /// row: the wings keep showing their artwork and meter while the title reads in the strip, so
    /// nothing hides behind the camera and no part of the surface is left empty.
    static let popupExtraWidth: CGFloat = 300
    static let popupExtraHeight: CGFloat = 36
    /// Inset between the shape's edge (past the ears) and popup content.
    static let popupContentInset: CGFloat = 12
    /// Vertical breathing room of compact content: icon height = housing height − this.
    static let compactContentInset: CGFloat = 12
    /// Room kept above and below wing content (artwork, meter, mark), and beside it in a popup.
    static let wingContentInset: CGFloat = 8
    /// Wing content size before the engine has measured anything: a floating capsule's.
    static let defaultWingContentSize: CGFloat = 20

    /// How large wing content may be, handed to modules through `EnvironmentValues.wingContentSize`:
    /// the surface's height minus the insets, so it follows the surface — 20 pt beside a floating
    /// capsule's rim, about the housing's height in the compact strip, and most of the surface
    /// while a popup hangs its title strip beneath the housing.
    static func wingContentSize(for state: NotchState, metrics: NotchLayoutMetrics) -> CGFloat {
        let height = state.isResting ? metrics.notchSize.height : shapeSize(for: state, metrics: metrics).height
        return max(12, height - 2 * wingContentInset)
    }
    /// Strip reserved above expanded content while another module's banner is showing, so the two
    /// never overlap.
    static let bannerHeight: CGFloat = 28
    /// Strip along the bottom of the expanded card that names the current screen and switches
    /// between them.
    static let switcherHeight: CGFloat = 26
    /// How far beyond the expanded surface the cursor may wander and still count as on it.
    static let graceMargin = CGSize(width: 32, height: 28)
    /// How far beside and below the surface a file drag still counts as aimed at it.
    static let dropDetectorMargin: CGFloat = 32

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
                return CGSize(width: floatingCompactSize.width + 100, height: floatingCompactSize.height + popupExtraHeight)
            case .expanded:
                // The same content area as over a housing: the card there is 150 high minus the
                // bottom inset, so the floating card gets one inset added to its 150.
                return CGSize(width: expandedContentSize.width, height: expandedContentSize.height + expandedContentInset)
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

    /// Size of the detector drawn behind the surface while a file drag is under way: the surface
    /// plus the margin on both sides and below (the top is the screen edge). A screen without a
    /// housing shows nothing when closed, so the detector takes the compact capsule's size there.
    static func dropDetectorSize(for state: NotchState, metrics: NotchLayoutMetrics) -> CGSize {
        var base = shapeSize(for: state, metrics: metrics)
        if base == .zero { base = floatingCompactSize }
        return CGSize(width: base.width + 2 * dropDetectorMargin, height: base.height + dropDetectorMargin)
    }

    /// Screen-space zone a file drag must reach to open the drop module, for the state the surface
    /// is in: the detector's footprint at the panel's top centre.
    static func dropZoneRect(panelFrame: CGRect, metrics: NotchLayoutMetrics, state: NotchState) -> CGRect {
        let size = dropDetectorSize(for: state, metrics: metrics)
        let top = topInset(for: metrics)
        return CGRect(
            x: panelFrame.midX - size.width / 2,
            y: panelFrame.maxY - top - size.height,
            width: size.width,
            height: size.height + top
        )
    }

    /// Where a point of the hosting view (top-left origin) falls inside the expanded module
    /// content, 0…1 in both axes and clamped to the edges; `nil` when the content has no area.
    static func expandedContentUnitPoint(viewPoint: CGPoint, metrics: NotchLayoutMetrics, showsBanner: Bool, showsSwitcher: Bool) -> CGPoint? {
        let state = NotchState.expanded(moduleID: "")
        let size = shapeSize(for: state, metrics: metrics, showsBanner: showsBanner, showsSwitcher: showsSwitcher)
        let inset = cornerRadii(for: state, style: metrics.style).ear + expandedContentInset
        let contentX = (metrics.panelSize.width - size.width) / 2 + inset
        let contentWidth = size.width - 2 * inset
        let contentTop = topInset(for: metrics) + expandedTopInset(for: metrics) + (showsBanner ? bannerHeight : 0)
        let contentHeight = size.height - expandedTopInset(for: metrics) - (showsBanner ? bannerHeight : 0) - (showsSwitcher ? switcherHeight : 0) - expandedContentInset
        guard contentWidth > 0, contentHeight > 0 else { return nil }
        return CGPoint(
            x: min(max((viewPoint.x - contentX) / contentWidth, 0), 1),
            y: min(max((viewPoint.y - contentTop) / contentHeight, 0), 1)
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
