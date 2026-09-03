// Adapted from MrKai77/DynamicNotchKit (MIT) — Sources/DynamicNotchKit/Views/NotchShape.swift.
// Changes: radii are clamped to the rect, a convex top radius was added for the floating style
// (screens without a housing), parameters were renamed and the geometry documented.

import SwiftUI

/// The notch silhouette.
///
/// - `earRadius`: concave curves where the flat top edge flares out into the screen edge. Zero
///   makes the top corners sharp (the closed state, coinciding with the physical housing).
/// - `bottomRadius`: convex rounded bottom corners.
/// - `topRadius`: convex rounded top corners, used only by the floating style. When it is
///   positive the ears are ignored, so a capsule can morph into a rounded card.
///
/// All three radii animate, so closed → compact → expanded is one continuous morph.
nonisolated struct NotchShape: Shape {
    var earRadius: CGFloat
    var bottomRadius: CGFloat
    var topRadius: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(earRadius, AnimatablePair(bottomRadius, topRadius)) }
        set {
            earRadius = newValue.first
            bottomRadius = newValue.second.first
            topRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let top = max(0, min(topRadius, rect.width / 2, rect.height / 2))
        let ear = top > 0 ? 0 : max(0, min(earRadius, rect.width / 2, rect.height / 2))
        let bottom = max(0, min(bottomRadius, rect.width / 2 - ear, rect.height - max(ear, top)))

        var path = Path()
        if top > 0 {
            // Floating style: rounded top corners.
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + top))
            path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        } else {
            // Housing style: the top edge is the screen edge; ears flare outward.
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.minX + ear, y: rect.minY + ear), control: CGPoint(x: rect.minX + ear, y: rect.minY))
        }

        path.addLine(to: CGPoint(x: rect.minX + ear, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: rect.minX + ear + bottom, y: rect.maxY), control: CGPoint(x: rect.minX + ear, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - ear - bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - ear, y: rect.maxY - bottom), control: CGPoint(x: rect.maxX - ear, y: rect.maxY))

        if top > 0 {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + top))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - top, y: rect.minY), control: CGPoint(x: rect.maxX, y: rect.minY))
        } else {
            path.addLine(to: CGPoint(x: rect.maxX - ear, y: rect.minY + ear))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - ear, y: rect.minY))
        }
        path.closeSubpath()
        return path
    }
}
