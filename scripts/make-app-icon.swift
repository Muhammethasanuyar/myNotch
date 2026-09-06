#!/usr/bin/swift
// Draws the app icon with Core Graphics and packs it into Resources/AppIcon.icns.
// Run from the repo root: `swift scripts/make-app-icon.swift`. Deterministic, no assets needed.

import AppKit

let canvas: CGFloat = 1024
let output = URL(fileURLWithPath: "Resources/AppIcon.icns")

func render() -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    // The macOS icon grid: the squircle fills 824 of 1024 points.
    let inset = (canvas - 824) / 2
    let squircle = CGRect(x: inset, y: inset, width: 824, height: 824)
    let body = CGPath(roundedRect: squircle, cornerWidth: 186, cornerHeight: 186, transform: nil)

    // Drop shadow under the body, as macOS icons carry.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.45))
    context.addPath(body)
    context.setFillColor(CGColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1))
    context.fillPath()
    context.restoreGState()

    // Body: a dark screen with a faint vertical gradient.
    context.saveGState()
    context.addPath(body)
    context.clip()
    let bodyGradient = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.20, green: 0.20, blue: 0.23, alpha: 1),
        CGColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
    ] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(bodyGradient, start: CGPoint(x: 0, y: squircle.maxY), end: CGPoint(x: 0, y: squircle.minY), options: [])

    // A thin lighter rim along the top edge, like a display bezel catching light.
    let rim = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.10),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)
    ] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(rim, start: CGPoint(x: 0, y: squircle.maxY), end: CGPoint(x: 0, y: squircle.maxY - 90), options: [])

    // The housing: a black tab hanging from the top edge with rounded bottom corners.
    let notchWidth: CGFloat = 300
    let notchHeight: CGFloat = 78
    let notch = CGRect(x: squircle.midX - notchWidth / 2, y: squircle.maxY - notchHeight, width: notchWidth, height: notchHeight + 40)
    let notchPath = CGPath(roundedRect: notch, cornerWidth: 34, cornerHeight: 34, transform: nil)
    context.addPath(notchPath)
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fillPath()

    // Beneath it, the live surface: four equaliser bars in the app's accent, glowing.
    let accent = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 1),
        CGColor(red: 0.69, green: 0.32, blue: 0.87, alpha: 1)
    ] as CFArray, locations: [0, 1])!
    let heights: [CGFloat] = [150, 250, 330, 200]
    let barWidth: CGFloat = 54
    let gap: CGFloat = 40
    let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    let baseline = squircle.minY + 214
    var x = squircle.midX - totalWidth / 2
    context.saveGState()
    context.setShadow(offset: .zero, blur: 40, color: CGColor(red: 0.45, green: 0.6, blue: 1, alpha: 0.55))
    for height in heights {
        let bar = CGPath(roundedRect: CGRect(x: x, y: baseline, width: barWidth, height: height), cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
        context.saveGState()
        context.addPath(bar)
        context.clip()
        context.drawLinearGradient(accent, start: CGPoint(x: x, y: baseline + height), end: CGPoint(x: x + barWidth, y: baseline), options: [])
        context.restoreGState()
        x += barWidth + gap
    }
    context.restoreGState()
    context.restoreGState()
    return context.makeImage()!
}

func write(_ image: CGImage, size: Int, to url: URL) throws {
    let scaled = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: scaled)!
    NSGraphicsContext.current = ctx
    ctx.cgContext.interpolationQuality = .high
    ctx.cgContext.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    try scaled.representation(using: .png, properties: [:])!.write(to: url)
}

let image = render()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("MyNotch-\(UUID().uuidString).iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, size) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    try write(image, size: size, to: iconset.appendingPathComponent("\(name).png"))
}
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed with \(iconutil.terminationStatus)") }
print("wrote \(output.path)")
