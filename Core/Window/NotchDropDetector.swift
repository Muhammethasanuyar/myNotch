// Adapted from Lakr233/NotchDrop (MIT): the near-transparent drop detector of NotchView.swift.

import SwiftUI

/// A shape the eye cannot see but the window server can. The panel is click-through wherever its
/// pixels are transparent, and that goes for file drags too: a drag aimed a little beside the
/// housing would fall through to the menu bar. At alpha 0.001 the pixels count as drawn, so the
/// drag reaches the panel and can open the module that takes drops. The root view draws this only
/// while a file drag is under way, so it never stands in the way of a click.
struct NotchDropDetector: View {
    let size: CGSize
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.black.opacity(0.001))
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
    }
}
