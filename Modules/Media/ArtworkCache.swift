import AppKit
import CoreImage
import SwiftUI

/// Artwork plus the accent colour extracted from it.
struct MediaArtwork: Equatable {
    let image: NSImage
    let accent: Color
}

/// Loads artwork once per track and keeps the last result, so a track change never flashes through
/// a placeholder.
@MainActor
final class ArtworkCache {
    private var entries: [String: MediaArtwork] = [:]
    private var inFlight: Set<String> = []
    /// Files written by providers that cannot hand out a URL.
    private let scratchDirectory: URL

    init() {
        scratchDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyNotchArtwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
    }

    func cached(for state: MediaState) -> MediaArtwork? {
        entries[state.artworkKey]
    }

    /// Fetches the artwork for `state`, or returns the cached copy. Providers that need to write the
    /// image out first are asked to do so here.
    func load(for state: MediaState, provider: any MediaProvider) async -> MediaArtwork? {
        let key = state.artworkKey
        if let cached = entries[key] { return cached }
        guard !inFlight.contains(key) else { return nil }
        inFlight.insert(key)
        defer { inFlight.remove(key) }

        var image: NSImage?
        switch state.artwork {
        case .url(let url):
            image = await Self.download(url)
        case .file(let path):
            image = NSImage(contentsOfFile: path)
        case nil:
            let destination = scratchDirectory.appendingPathComponent("\(key.hashValue).artwork")
            if (try? await provider.prepareArtwork(destination: destination)) == true {
                image = NSImage(contentsOf: destination)
                try? FileManager.default.removeItem(at: destination)
            }
        }

        guard let image else { return nil }
        let artwork = MediaArtwork(image: image, accent: Self.accent(from: image))
        entries[key] = artwork
        // Keep the cache small: only the handful of tracks around the current one matter.
        if entries.count > 12 {
            entries.removeValue(forKey: entries.keys.first { $0 != key } ?? key)
        }
        return artwork
    }

    private static func download(_ url: URL) async -> NSImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return NSImage(data: data)
    }

    /// Average colour of the artwork, pushed towards something that reads on black.
    nonisolated static func accent(from image: NSImage) -> Color {
        guard let tiff = image.tiffRepresentation, let ciImage = CIImage(data: tiff) else { return .white }
        let parameters: [String: Any] = [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: CIVector(cgRect: ciImage.extent)
        ]
        guard let output = CIFilter(name: "CIAreaAverage", parameters: parameters)?.outputImage else { return .white }

        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let average = NSColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        ).usingColorSpace(.deviceRGB)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 1
        average?.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(nsColor: NSColor(
            hue: hue,
            saturation: min(1, max(0.55, saturation * 1.4)),
            brightness: min(0.95, max(0.75, brightness * 1.25)),
            alpha: 1
        ))
    }
}
