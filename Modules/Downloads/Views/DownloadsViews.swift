import SwiftUI
import UniformTypeIdentifiers

enum DownloadsStyle {
    static let accent = Color(red: 0.4, green: 0.8, blue: 0.55)
}

/// Compact leading wing: a down arrow inside a ring that follows the aggregate progress — value
/// driven, so it only redraws when a scan moves it — or breathes (Core Animation) when no total is known.
struct DownloadsCompactLeading: View {
    let service: DownloadsService
    @Environment(\.wingContentSize) private var size

    var body: some View {
        let progress = DownloadsRules.aggregateProgress(service.items)
        ZStack {
            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 2)
            if let progress {
                Circle()
                    .trim(from: 0, to: max(0.02, progress))
                    .stroke(DownloadsStyle.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.4), value: progress)
                Image(systemName: "arrow.down")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(DownloadsStyle.accent)
            } else {
                PulsingSymbol(systemName: "arrow.down", pointSize: size * 0.42, weight: .bold, color: DownloadsStyle.accent, isActive: true)
            }
        }
        .frame(width: size * 0.85, height: size * 0.85)
    }
}

/// Compact trailing wing: the percentage, or an ellipsis while the total is unknown.
struct DownloadsCompactTrailing: View {
    let service: DownloadsService
    @Environment(\.wingContentSize) private var size

    var body: some View {
        let active = service.items.filter { !$0.isFinished }
        let text: String = if let progress = DownloadsRules.aggregateProgress(service.items) {
            L("downloads.percent", "\(Int((progress * 100).rounded()))%")
        } else if active.count > 1 {
            String(active.count)
        } else {
            "…"
        }
        Text(text)
            .font(.system(size: size * 0.5, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .contentTransition(.numericText())
            .animation(.default, value: text)
            .lineLimit(1)
    }
}

private enum DownloadsFocus: Hashable {
    case row(String)
    case empty
}

/// The card: transfers in flight on top, recent ones under them, each with its icon, a progress bar
/// and its size. Tap opens a finished file; the tray button puts it on the shelf.
struct DownloadsExpandedView: View {
    let module: DownloadsModule

    @State private var focus: DownloadsFocus?
    @State private var appeared = false

    private var service: DownloadsService { module.service }

    var body: some View {
        Group {
            if service.access == .denied {
                message(symbol: "lock.fill", title: L("downloads.denied", "Downloads folder not allowed"), detail: L("downloads.denied.help", "Allow MyNotch under Privacy & Security → Files and Folders → Downloads."))
            } else if service.items.isEmpty {
                message(symbol: "arrow.down.circle", title: L("downloads.empty", "No downloads"), detail: L("downloads.empty.help", "Safari, Chrome and friends show up here while they download and for a while after."))
                    .spotlight(DownloadsFocus.empty, focus: $focus, accent: DownloadsStyle.accent)
            } else {
                list
            }
        }
        .foregroundStyle(.white)
        .overlay(alignment: .bottomLeading) {
            if let focus, let text = explanation(for: focus) {
                NotchExplanationBubble(text: text, accent: DownloadsStyle.accent)
                    .padding(.bottom, 2)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: focus)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: service.items.map(\.id))
        .onAppear { appeared = true }
    }

    private func message(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(DownloadsStyle.accent)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 6) {
                ForEach(Array(service.items.prefix(6).enumerated()), id: \.element.id) { index, item in
                    DownloadRow(item: item, canOffer: module.canOfferFiles && item.isFinished) {
                        service.open(item)
                    } offer: {
                        module.offerToShelf(item)
                    }
                    .spotlight(DownloadsFocus.row(item.id), focus: $focus, accent: DownloadsStyle.accent)
                    .reveal(appeared, index: index)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func explanation(for focus: DownloadsFocus) -> String? {
        switch focus {
        case .empty:
            return L("downloads.explain.empty", "The Downloads folder is watched only while this module is on; a scan runs when a browser writes, never on a timer.")
        case .row(let id):
            guard let item = service.items.first(where: { $0.id == id }) else { return nil }
            if item.isFinished {
                return L("downloads.explain.finished", "\(DownloadsRules.sizeText(item)) · tap to open; the tray puts a copy on the shelf.")
            }
            return item.totalBytes == nil
                ? L("downloads.explain.indeterminate", "\(DownloadsRules.sizeText(item)) so far. This browser does not say how big the file will be, so the bar just moves.")
                : L("downloads.explain.progress", "\(DownloadsRules.sizeText(item)) · \(DownloadsRules.percentText(item)). Safari reports the total, so the bar is exact.")
        }
    }
}

/// One transfer.
struct DownloadRow: View {
    let item: DownloadItem
    let canOffer: Bool
    let open: () -> Void
    let offer: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                bar
                Text(DownloadsRules.sizeText(item))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 4)
            if item.isFinished {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DownloadsStyle.accent)
                if canOffer {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .foregroundStyle(.white.opacity(0.8))
                        .notchTap(perform: offer)
                }
            } else {
                Text(DownloadsRules.percentText(item))
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(Rectangle())
        .notchTap(isEnabled: item.isFinished, perform: open)
    }

    private var icon: NSImage {
        if item.isFinished, FileManager.default.fileExists(atPath: item.destination.path) {
            return NSWorkspace.shared.icon(forFile: item.destination.path)
        }
        let type = UTType(filenameExtension: item.destination.pathExtension) ?? .data
        return NSWorkspace.shared.icon(for: type)
    }

    @ViewBuilder
    private var bar: some View {
        let progress = item.isFinished ? 1 : DownloadsRules.progress(item)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                if let progress {
                    Capsule()
                        .fill(DownloadsStyle.accent)
                        .frame(width: max(4, proxy.size.width * progress))
                        .animation(.linear(duration: 0.4), value: progress)
                } else {
                    // No total: a short segment that rides along with the bytes so far.
                    Capsule()
                        .fill(DownloadsStyle.accent.opacity(0.7))
                        .frame(width: proxy.size.width * 0.25)
                        .offset(x: proxy.size.width * 0.75 * CGFloat((Double(item.bytesSoFar / 65_536) / 20).truncatingRemainder(dividingBy: 1)))
                        .animation(.linear(duration: 0.4), value: item.bytesSoFar)
                }
            }
        }
        .frame(height: 4)
    }
}
