import AppKit
import SwiftUI

/// Something that can hand the bars real levels, one value per bar in 0…1. The engine defines
/// the seam; the media module's `AudioMeter` fills it.
@MainActor
protocol EqualizerLevelFeed: AnyObject {
    func addLevelObserver(_ owner: AnyObject, _ handler: @escaping @MainActor ([Float]) -> Void)
    func removeLevelObserver(_ owner: AnyObject)
}

/// Four bars that dance while something plays and rest low when it does not. Each bar is a layer
/// with its own Core Animation scale loop, so the meter costs the app nothing per frame; the
/// SwiftUI `TimelineView` version re-rendered the compact strip 24 times a second (~5% CPU while
/// music played, 2026-09-06 measurement). With a `feed`, the bars follow real levels instead —
/// still through Core Animation, one short transaction per update, no SwiftUI redraw.
struct EqualizerBars: NSViewRepresentable {
    let isPlaying: Bool
    var color: Color = .white
    var barCount = 4
    /// Bars and the gaps between them grow with the wing they sit in.
    var barWidth: CGFloat = 2
    /// Real levels, when the visualizer is on; `nil` keeps the autonomous dance.
    var feed: (any EqualizerLevelFeed)?
    var mode: EqualizerMode?

    init(isPlaying: Bool, color: Color = .white, barCount: Int = 4, barWidth: CGFloat = 2, feed: (any EqualizerLevelFeed)? = nil, mode: EqualizerMode? = nil) {
        self.isPlaying = isPlaying
        self.color = color
        self.barCount = barCount
        self.barWidth = barWidth
        self.feed = feed
        self.mode = mode
    }

    func makeNSView(context: Context) -> EqualizerBarsView {
        EqualizerBarsView()
    }

    func updateNSView(_ view: EqualizerBarsView, context: Context) {
        let resolved = mode ?? (isPlaying ? .dancing : .resting)
        view.apply(barCount: barCount, barWidth: barWidth, color: NSColor(color), mode: resolved, feed: feed)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: EqualizerBarsView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: barWidth * CGFloat(2 * barCount - 1), height: barWidth * 7))
    }
}

/// The layer-backed view behind `EqualizerBars`.
final class EqualizerBarsView: NSView {
    private var bars: [CALayer] = []
    private var barWidth: CGFloat = 2
    private var mode: EqualizerMode = .resting
    private weak var feed: (any EqualizerLevelFeed)?
    private var isObserving = false
    /// Slightly different periods per bar, so the pattern never visibly repeats.
    private static let periods: [CFTimeInterval] = [0.46, 0.61, 0.53, 0.72, 0.58, 0.67]
    private static let restingScale: CGFloat = 0.2
    private static let animationKey = "dance"

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("EqualizerBarsView does not support NSCoding")
    }

    func apply(barCount: Int, barWidth: CGFloat, color: NSColor, mode: EqualizerMode, feed: (any EqualizerLevelFeed)?) {
        guard let layer else { return }
        var forceMode = false
        if bars.count != barCount {
            bars.forEach { $0.removeFromSuperlayer() }
            bars = (0..<barCount).map { _ in
                let bar = CALayer()
                bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                layer.addSublayer(bar)
                return bar
            }
            forceMode = true
        }
        self.barWidth = barWidth
        for bar in bars {
            bar.backgroundColor = color.cgColor
            bar.cornerRadius = barWidth / 2
        }
        layoutBars()
        if feed !== self.feed {
            stopObserving()
            self.feed = feed
        }
        guard forceMode || mode != self.mode else {
            observeIfNeeded()
            return
        }
        self.mode = mode
        for (index, bar) in bars.enumerated() {
            switch mode {
            case .dancing:
                let dance = CABasicAnimation(keyPath: "transform.scale.y")
                dance.fromValue = 0.25
                dance.toValue = 1.0
                dance.duration = Self.periods[index % Self.periods.count]
                dance.autoreverses = true
                dance.repeatCount = .infinity
                dance.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                dance.timeOffset = Double(index) * 0.17
                bar.transform = CATransform3DIdentity
                bar.add(dance, forKey: Self.animationKey)
            case .resting:
                bar.removeAnimation(forKey: Self.animationKey)
                bar.transform = CATransform3DMakeScale(1, Self.restingScale, 1)
            case .live:
                bar.removeAnimation(forKey: Self.animationKey)
            }
        }
        observeIfNeeded()
    }

    /// Real levels: each bar glides to its new height in a short transaction.
    func setLevels(_ levels: [Float]) {
        guard mode == .live else { return }
        let heights = AudioMeterRules.barLevels(levels, barCount: bars.count)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.05)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        for (bar, height) in zip(bars, heights) {
            bar.transform = CATransform3DMakeScale(1, CGFloat(max(0.08, height)), 1)
        }
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopObserving()
        } else {
            observeIfNeeded()
        }
    }

    private func observeIfNeeded() {
        guard window != nil, mode == .live, let feed, !isObserving else { return }
        isObserving = true
        feed.addLevelObserver(self) { [weak self] levels in self?.setLevels(levels) }
    }

    private func stopObserving() {
        guard isObserving else { return }
        isObserving = false
        feed?.removeLevelObserver(self)
    }

    override func layout() {
        super.layout()
        layoutBars()
    }

    /// Bars centred in the view, one bar's width apart; the transform is left alone so a running
    /// dance survives a resize (the wing grows when a popup opens).
    private func layoutBars() {
        let count = CGFloat(bars.count)
        guard count > 0 else { return }
        let totalWidth = barWidth * (2 * count - 1)
        let startX = (bounds.width - totalWidth) / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            let frame = CGRect(x: startX + CGFloat(index) * barWidth * 2, y: 0, width: barWidth, height: bounds.height)
            bar.bounds = CGRect(origin: .zero, size: frame.size)
            bar.position = CGPoint(x: frame.midX, y: frame.midY)
        }
        CATransaction.commit()
    }
}
