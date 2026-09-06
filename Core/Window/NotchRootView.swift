import SwiftUI

/// Root of the SwiftUI content hosted in the notch panel: one black surface whose size, corner
/// radii and content follow `NotchViewModel.state`, so every state change is a single morph.
struct NotchRootView: View {
    let model: NotchViewModel
    let metrics: NotchLayoutMetrics
    let content: NotchContentProvider
    /// Paints the panel footprint red and outlines the surface in blue so alignment can be checked.
    var debugTint = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var morphNamespace

    var body: some View {
        let state = model.state
        // Read here, in the body, so the strip follows the modules' own observable state.
        let screens = expandedScreens(for: state)
        let size = NotchLayout.shapeSize(
            for: state,
            metrics: metrics,
            showsBanner: model.banner != nil,
            showsSwitcher: ModuleScreenList.shouldShow(screens)
        )
        let radii = NotchLayout.cornerRadii(for: state, style: metrics.style)

        ZStack(alignment: .top) {
            if debugTint {
                Color.red.opacity(0.25)
            }
            // Behind the surface, only while a file drag is under way and a module would take it.
            if model.isDragSessionActive, content.dropTargetModuleID() != nil {
                NotchDropDetector(size: NotchLayout.dropDetectorSize(for: state, metrics: metrics), cornerRadius: max(radii.bottom, 10))
                    .padding(.top, NotchLayout.topInset(for: metrics))
            }
            if size != .zero {
                surface(state: state, size: size, radii: radii, screens: screens)
                    .frame(width: size.width, height: size.height)
                    .padding(.top, NotchLayout.topInset(for: metrics))
            }
        }
        .frame(width: metrics.panelSize.width, height: metrics.panelSize.height, alignment: .top)
        .animation(Anim.morph(to: state, settings: model.animation, reduceMotion: reduceMotion), value: state)
        .animation(Anim.subtle, value: model.banner)
        .animation(Anim.subtle, value: screens)
    }

    /// The screens the switcher offers, or none when the card is not open.
    private func expandedScreens(for state: NotchState) -> [ModuleScreen] {
        guard case .expanded(let moduleID) = state else { return [] }
        return content.screens(moduleID)
    }

    private func surface(state: NotchState, size: CGSize, radii: NotchLayout.CornerRadii, screens: [ModuleScreen]) -> some View {
        let shape = NotchShape(earRadius: radii.ear, bottomRadius: radii.bottom, topRadius: radii.top)
        return ZStack(alignment: .top) {
            shape
                .fill(.black)
                .shadow(color: .black.opacity(state.isResting ? 0 : 0.45), radius: state.isResting ? 0 : 10, y: 4)
            contentLayer(state: state, size: size, radii: radii, screens: screens)
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(shape)
            if debugTint {
                shape.stroke(.blue, lineWidth: 1)
            }
        }
        .contentShape(shape)
        .onHover { model.hoverChanged($0) }
    }

    @ViewBuilder
    private func contentLayer(state: NotchState, size: CGSize, radii: NotchLayout.CornerRadii, screens: [ModuleScreen]) -> some View {
        switch state {
        case .closed:
            EmptyView()
        case .compact, .popup:
            compactLayer(state: state, size: size, radii: radii)
                .frame(width: size.width, height: size.height, alignment: .top)
        case .expanded(let moduleID):
            expandedLayer(moduleID: moduleID, size: size, radii: radii, screens: screens)
        }
    }

    /// The compact row, and the popup that grows out of it: one HStack for both states, so the
    /// wings keep their identity (and their artwork and meter) while the surface widens. Wing
    /// content follows the surface's height, so in a popup the artwork spans the surface beside
    /// the housing while the title reads on the strip beneath it.
    private func compactLayer(state: NotchState, size: CGSize, radii: NotchLayout.CornerRadii) -> some View {
        let isPopup = state.isPopup
        // Beside the housing the wings have a fixed width the shape was sized for; in a popup they
        // take their natural width plus breathing room, and the strip gets what is left.
        let wingWidth: CGFloat? = metrics.style == .notch && !isPopup ? NotchLayout.compactWingWidth(notchHeight: size.height) : nil
        let wingPadding: CGFloat = isPopup ? NotchLayout.wingContentInset : 0
        return HStack(spacing: 0) {
            content.compactLeading(morphNamespace)
                .frame(width: wingWidth, height: size.height)
                .padding(.horizontal, wingPadding)
                .transition(NotchTransitions.compactWing(edge: .leading))
            if case .popup(let event) = state {
                VStack(spacing: 0) {
                    // Nothing goes behind the camera: the strip starts under the housing.
                    Color.clear
                        .frame(height: metrics.style == .notch ? metrics.notchSize.height : 0)
                    content.popup(event, morphNamespace)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, NotchLayout.popupContentInset)
                .transition(NotchTransitions.popup)
            } else {
                Spacer(minLength: metrics.style == .notch ? metrics.notchSize.width : 12)
            }
            content.compactTrailing(morphNamespace)
                .frame(width: wingWidth, height: size.height)
                .padding(.horizontal, wingPadding)
                .transition(NotchTransitions.compactWing(edge: .trailing))
        }
        .padding(.horizontal, radii.ear + (metrics.style == .notch ? 0 : 12))
        .environment(\.wingContentSize, NotchLayout.wingContentSize(for: state, metrics: metrics))
    }

    private func expandedLayer(moduleID: String, size: CGSize, radii: NotchLayout.CornerRadii, screens: [ModuleScreen]) -> some View {
        // The banner sits in a strip of its own above the module's view and the screen switcher in
        // one below it; the surface grew by their heights, so nothing covers anything.
        let showsSwitcher = ModuleScreenList.shouldShow(screens)
        return VStack(spacing: 0) {
            if let banner = model.banner {
                content.popup(banner, morphNamespace)
                    .padding(.horizontal, 10)
                    .frame(height: NotchLayout.bannerHeight - 6)
                    .background(.white.opacity(0.1), in: Capsule())
                    .padding(.horizontal, radii.ear + NotchLayout.expandedContentInset)
                    .padding(.top, NotchLayout.expandedTopInset(for: metrics))
                    .transition(NotchTransitions.popup)
            }
            content.expanded(moduleID, morphNamespace)
                .padding(.top, model.banner == nil ? NotchLayout.expandedTopInset(for: metrics) : 6)
                .padding(.horizontal, radii.ear + NotchLayout.expandedContentInset)
                .padding(.bottom, showsSwitcher ? 2 : NotchLayout.expandedContentInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(NotchTransitions.expandedContent)
            if showsSwitcher {
                NotchScreenSwitcher(screens: screens, activeID: content.activeScreenID(moduleID), onSelect: content.selectScreen)
                    .frame(height: NotchLayout.switcherHeight - 6)
                    .padding(.horizontal, radii.ear + NotchLayout.expandedContentInset)
                    .padding(.bottom, NotchLayout.expandedContentInset - 6)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }
}
