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
        case .compact:
            compactLayer(radii: radii)
        case .expanded(let moduleID):
            expandedLayer(moduleID: moduleID, size: size, radii: radii, screens: screens)
        case .popup(let event):
            content.popup(event, morphNamespace)
                .padding(.horizontal, radii.ear + 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(NotchTransitions.popup)
        }
    }

    private func compactLayer(radii: NotchLayout.CornerRadii) -> some View {
        let height = metrics.notchSize.height
        let wing = metrics.style == .notch ? NotchLayout.compactWingWidth(notchHeight: height) : nil
        return HStack(spacing: 0) {
            content.compactLeading(morphNamespace)
                .frame(width: wing, height: height)
                .transition(NotchTransitions.compactWing(edge: .leading))
            if metrics.style == .notch {
                Spacer(minLength: 0).frame(width: metrics.notchSize.width)
            } else {
                Spacer(minLength: 12)
            }
            content.compactTrailing(morphNamespace)
                .frame(width: wing, height: height)
                .transition(NotchTransitions.compactWing(edge: .trailing))
        }
        .padding(.horizontal, radii.ear + (metrics.style == .notch ? 0 : 12))
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
                NotchScreenSwitcher(screens: screens, activeID: moduleID) { model.expand(moduleID: $0) }
                    .frame(height: NotchLayout.switcherHeight - 6)
                    .padding(.horizontal, radii.ear + NotchLayout.expandedContentInset)
                    .padding(.bottom, NotchLayout.expandedContentInset - 6)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }
}
