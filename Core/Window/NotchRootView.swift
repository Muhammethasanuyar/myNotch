import SwiftUI

/// Root of the SwiftUI content hosted in the notch panel.
/// Phase 0 renders only the closed state: a black shape that coincides with the physical notch.
struct NotchRootView: View {
    let metrics: NotchLayoutMetrics
    /// Paints the panel footprint red and the notch rectangle blue so alignment can be checked visually.
    let debugTint: Bool

    var body: some View {
        ZStack(alignment: .top) {
            if debugTint {
                Color.red.opacity(0.25)
            }
            UnevenRoundedRectangle(
                bottomLeadingRadius: NotchLayout.closedCornerRadius,
                bottomTrailingRadius: NotchLayout.closedCornerRadius,
                style: .continuous
            )
            .fill(.black)
            .overlay {
                if debugTint {
                    Color.blue.opacity(0.5)
                }
            }
            .frame(width: metrics.notchSize.width, height: metrics.notchSize.height)
        }
        .frame(width: metrics.panelSize.width, height: metrics.panelSize.height, alignment: .top)
    }
}
