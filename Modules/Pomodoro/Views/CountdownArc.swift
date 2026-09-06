import AppKit
import SwiftUI

/// A ring that empties as a phase runs out. The stroke is a Core Animation `strokeEnd` animation
/// whose duration is the time left, so the app does nothing per frame; paused, the ring holds.
struct CountdownArc: NSViewRepresentable {
    /// Fraction of the phase still ahead right now, 0…1.
    let fraction: Double
    /// Seconds until the ring is empty while running; `nil` holds the ring where it is.
    let runningRemaining: TimeInterval?
    /// Identity of the run (the phase's end date): a new run restarts the animation, a re-render
    /// of the same run leaves it alone.
    let runID: Date?
    let color: Color
    var trackColor: Color = .white.opacity(0.15)
    var lineWidth: CGFloat = 4

    func makeNSView(context: Context) -> CountdownArcView {
        CountdownArcView()
    }

    func updateNSView(_ view: CountdownArcView, context: Context) {
        view.apply(fraction: fraction, remaining: runningRemaining, runID: runID, color: NSColor(color), track: NSColor(trackColor), lineWidth: lineWidth)
    }
}

/// The layer-backed view behind `CountdownArc`.
final class CountdownArcView: NSView {
    private let track = CAShapeLayer()
    private let progress = CAShapeLayer()
    private var runID: Date?
    private var lineWidth: CGFloat = 4
    private static let animationKey = "countdown"

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for shape in [track, progress] {
            shape.fillColor = nil
            shape.lineCap = .round
            layer?.addSublayer(shape)
        }
        track.strokeEnd = 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CountdownArcView does not support NSCoding")
    }

    func apply(fraction: Double, remaining: TimeInterval?, runID: Date?, color: NSColor, track trackColor: NSColor, lineWidth: CGFloat) {
        self.lineWidth = lineWidth
        track.strokeColor = trackColor.cgColor
        progress.strokeColor = color.cgColor
        track.lineWidth = lineWidth
        progress.lineWidth = lineWidth
        layoutRing()

        if let remaining, remaining > 0 {
            guard runID != self.runID || progress.animation(forKey: Self.animationKey) == nil else { return }
            self.runID = runID
            let countdown = CABasicAnimation(keyPath: "strokeEnd")
            countdown.fromValue = fraction
            countdown.toValue = 0
            countdown.duration = remaining
            countdown.timingFunction = CAMediaTimingFunction(name: .linear)
            countdown.fillMode = .forwards
            countdown.isRemovedOnCompletion = false
            setStrokeEnd(0)
            progress.add(countdown, forKey: Self.animationKey)
        } else {
            self.runID = nil
            progress.removeAnimation(forKey: Self.animationKey)
            setStrokeEnd(fraction)
        }
    }

    private func setStrokeEnd(_ value: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progress.strokeEnd = value
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        layoutRing()
    }

    /// A circle starting at twelve o'clock and running clockwise, inset by half the stroke.
    private func layoutRing() {
        let radius = (min(bounds.width, bounds.height) - lineWidth) / 2
        guard radius > 0 else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for shape in [track, progress] {
            shape.frame = bounds
            shape.path = path
        }
        CATransaction.commit()
    }
}
