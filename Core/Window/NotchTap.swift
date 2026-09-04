import SwiftUI

/// A tap inside the notch panel.
///
/// The panel never activates, so macOS swallows the first plain click as the window-activation
/// click and `onTapGesture` never fires; a zero-distance drag that ends where it started does.
struct NotchTapGesture: ViewModifier {
    let isEnabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 0).onEnded { value in
                let stayedPut = abs(value.translation.width) < 20 && abs(value.translation.height) < 20
                if stayedPut, isEnabled { action() }
            }
        )
    }
}

extension View {
    /// Taps that work in a non-activating panel; see `NotchTapGesture`.
    func notchTap(isEnabled: Bool = true, perform action: @escaping () -> Void) -> some View {
        modifier(NotchTapGesture(isEnabled: isEnabled, action: action))
    }
}
