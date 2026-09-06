import AppKit
import SwiftUI

/// An SF Symbol whose breathing is a Core Animation opacity loop. The render server runs it, so an
/// always-on pulse costs the app nothing; SwiftUI's repeating `symbolEffect(.pulse)` re-rendered
/// the whole notch card on every frame instead (~14% CPU on the Claude card, 2026-09-06 bisect).
/// Use it for every ambient, repeating animation; one-shot effects (`.bounce` on a value change)
/// stay in SwiftUI.
struct PulsingSymbol: NSViewRepresentable {
    let systemName: String
    let pointSize: CGFloat
    var weight: NSFont.Weight = .regular
    let color: Color
    /// Whether the breath runs; the symbol stays fully visible when it does not.
    var isActive: Bool
    /// Opacity at the bottom of the breath.
    var floor: Double = 0.3
    /// One way of the breath, in seconds; the loop reverses and repeats.
    var period: TimeInterval = 0.9

    private static let animationKey = "breath"

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.wantsLayer = true
        view.imageScaling = .scaleNone
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        view.image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
        view.contentTintColor = NSColor(color)
        guard let layer = view.layer else { return }
        if isActive {
            guard layer.animation(forKey: Self.animationKey) == nil else { return }
            let breath = CABasicAnimation(keyPath: "opacity")
            breath.fromValue = 1
            breath.toValue = floor
            breath.duration = period
            breath.autoreverses = true
            breath.repeatCount = .infinity
            breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(breath, forKey: Self.animationKey)
        } else {
            layer.removeAnimation(forKey: Self.animationKey)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        nsView.image?.size
    }
}
