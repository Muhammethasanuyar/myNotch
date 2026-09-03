import SwiftUI

/// Enter/exit choreography for content inside the surface: blur + scale + fade.
enum NotchTransitions {
    /// Compact wings slide out of the housing.
    static func compactWing(edge: HorizontalEdge) -> AnyTransition {
        let anchor: UnitPoint = edge == .leading ? .trailing : .leading
        return .modifier(active: BlurScaleModifier(blur: 8, scale: 0.4, anchor: anchor),
                         identity: BlurScaleModifier(blur: 0, scale: 1, anchor: anchor))
            .combined(with: .opacity)
    }

    /// Expanded content unfolds downward from the housing.
    static var expandedContent: AnyTransition {
        .modifier(active: BlurScaleModifier(blur: 10, scale: 0.85, anchor: .top),
                  identity: BlurScaleModifier(blur: 0, scale: 1, anchor: .top))
            .combined(with: .opacity)
    }

    /// Popups pop in slightly smaller and settle.
    static var popup: AnyTransition {
        .modifier(active: BlurScaleModifier(blur: 6, scale: 0.9, anchor: .top),
                  identity: BlurScaleModifier(blur: 0, scale: 1, anchor: .top))
            .combined(with: .opacity)
    }
}

private struct BlurScaleModifier: ViewModifier {
    let blur: CGFloat
    let scale: CGFloat
    let anchor: UnitPoint

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .scaleEffect(scale, anchor: anchor)
    }
}
