import SwiftUI

enum ShelfStyle {
    static let accent = Color(red: 0.45, green: 0.72, blue: 1.0)
    static let airDrop = Color(red: 0.35, green: 0.62, blue: 1.0)
}

/// Compact leading wing: the tray.
struct ShelfCompactLeading: View {
    @Environment(\.wingContentSize) private var size

    var body: some View {
        Image(systemName: "tray.full.fill")
            .font(.system(size: size * 0.6, weight: .semibold))
            .foregroundStyle(ShelfStyle.accent)
    }
}

/// Compact trailing wing: how many files are on it.
struct ShelfCompactTrailing: View {
    let store: ShelfStore
    @Environment(\.wingContentSize) private var size

    var body: some View {
        Text(ShelfRules.badgeText(count: store.items.count))
            .font(.system(size: size * 0.5, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .contentTransition(.numericText())
            .animation(.default, value: store.items.count)
    }
}

/// What the cursor is resting on inside the card.
private enum ShelfFocus: Hashable {
    case airDrop
    case hint
    case item(UUID)
}

/// The card: an AirDrop target on the left, the shelf on the right. A drag over the card lights
/// the zone it would land in; items open on a tap, leave on the ✕ (or an Option-tap) and can be
/// dragged out again.
struct ShelfExpandedView: View {
    let store: ShelfStore

    @State private var focus: ShelfFocus?
    @State private var appeared = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            airDropZone
                .frame(width: 120)
                .frame(maxHeight: .infinity)
                .reveal(appeared, index: 0)
            shelf
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .reveal(appeared, index: 1)
        }
        .foregroundStyle(.white)
        .overlay(alignment: .bottomLeading) {
            if let focus {
                NotchExplanationBubble(text: explanation(for: focus), accent: ShelfStyle.accent)
                    .padding(.bottom, 2)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: focus)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: store.dropHighlight)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: store.items.map(\.id))
        .onAppear { appeared = true }
    }

    private var airDropZone: some View {
        let targeted = store.dropHighlight == .airDrop
        let enabled = !store.items.isEmpty && ShelfShare.isAirDropAvailable
        return VStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.right")
                .font(.system(size: 26, weight: .medium))
                .symbolEffect(.bounce, value: targeted)
            Text(L("shelf.airdrop", "AirDrop"))
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(targeted ? .white : ShelfStyle.airDrop.opacity(enabled ? 0.95 : 0.55))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ShelfStyle.airDrop.opacity(targeted ? 0.45 : 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(ShelfStyle.airDrop.opacity(targeted ? 0.9 : 0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
        .scaleEffect(targeted ? 1.03 : 1)
        .spotlight(ShelfFocus.airDrop, focus: $focus, accent: ShelfStyle.airDrop)
        .notchTap(isEnabled: enabled) {
            ShelfShare.airDrop(store.items.map(\.fileURL))
        }
    }

    @ViewBuilder
    private var shelf: some View {
        let targeted = store.dropHighlight == .shelf
        Group {
            if store.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(ShelfStyle.accent)
                    Text(L("shelf.empty", "Drop files onto the notch"))
                        .font(.system(size: 12, weight: .semibold))
                    Text(ShelfRules.keepIntervalTitle(store.keepInterval) == ShelfRules.keepIntervalTitle(0)
                         ? L("shelf.empty.forever", "Copies stay until you remove them.")
                         : L("shelf.empty.keep", "Copies stay for \(ShelfRules.keepIntervalTitle(store.keepInterval)), then leave on their own."))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .spotlight(ShelfFocus.hint, focus: $focus, accent: ShelfStyle.accent)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(store.items) { item in
                            ShelfItemView(item: item, isFocused: focus == .item(item.id)) {
                                Task { await store.remove(item) }
                            } open: {
                                store.open(item)
                            }
                            .spotlight(ShelfFocus.item(item.id), focus: $focus, accent: ShelfStyle.accent)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ShelfStyle.accent.opacity(targeted ? 0.28 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(ShelfStyle.accent.opacity(targeted ? 0.8 : 0.18), lineWidth: 1.5)
        )
    }

    private func explanation(for focus: ShelfFocus) -> String {
        switch focus {
        case .airDrop:
            return store.items.isEmpty
                ? L("shelf.explain.airdrop.empty", "Drop a file here to send it straight to AirDrop; tap it later to send everything on the shelf.")
                : L("shelf.explain.airdrop", "Sends every file on the shelf with AirDrop. Drop a file on this side to send just that one.")
        case .hint:
            return L("shelf.explain.hint", "Drag a file onto the notch: it opens, keeps a copy here and lets you drag it into another app later.")
        case .item(let id):
            if let item = store.items.first(where: { $0.id == id }) {
                let size = ShelfRules.formatBytes(item.record.byteCount)
                let expiry = ShelfRules.expiry(addedAt: item.record.addedAt, keepInterval: store.keepInterval)
                    .map { $0.formatted(.relative(presentation: .named)) }
                return expiry.map { L("shelf.explain.item", "\(size) · tap to open, drag to move on, ✕ to remove. Leaves \($0).") }
                    ?? L("shelf.explain.item.forever", "\(size) · tap to open, drag to move on, ✕ to remove.")
            }
            return ""
        }
    }
}

/// One file: its preview (or icon), its name, a ✕ while the cursor rests on it.
struct ShelfItemView: View {
    let item: ShelfItem
    let isFocused: Bool
    let remove: () -> Void
    let open: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ShelfThumbnail(item: item)
                .frame(width: 46, height: 46)
                .overlay(alignment: .topTrailing) {
                    if isFocused {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.black, .white.opacity(0.9))
                            .offset(x: 6, y: -6)
                            .notchTap(perform: remove)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            Text(item.fileName)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 64)
        }
        .padding(.top, 4)
        .contentShape(Rectangle())
        .draggable(item)
        .notchTap {
            if NSEvent.modifierFlags.contains(.option) { remove() } else { open() }
        }
    }
}

/// The preview written by the store, or the file's own icon until it exists.
private struct ShelfThumbnail: View {
    let item: ShelfItem
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.white.opacity(0.08))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(3)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.fileURL.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(6)
            }
        }
        .task(id: item.previewURL) {
            guard let url = item.previewURL else { image = nil; return }
            image = await Task.detached { NSImage(contentsOf: url) }.value
        }
    }
}
