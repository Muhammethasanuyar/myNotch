import SwiftUI

/// What is on the shelf, where the copies live and how long they stay.
struct ShelfPane: View {
    @Bindable var store: SettingsStore
    let module: ShelfModule?

    var body: some View {
        if let module {
            content(module.store)
        } else {
            ContentUnavailableView(L("settings.shelf.missing", "The shelf module is not registered."), systemImage: "tray.full.fill")
        }
    }

    private func content(_ shelf: ShelfStore) -> some View {
        SettingsForm {
            Section(L("settings.shelf.status", "On the shelf")) {
                StatusRow(
                    tone: shelf.items.isEmpty ? .neutral : .ok,
                    title: countTitle(shelf),
                    detail: shelf.root.path(percentEncoded: false)
                )
                if let error = shelf.lastError {
                    StatusRow(tone: .problem, title: L("settings.shelf.error", "The last file operation failed"), detail: error)
                }
                HStack(spacing: 8) {
                    Button(L("settings.shelf.reveal", "Show in Finder")) {
                        shelf.revealInFinder()
                    }
                    .controlSize(.small)
                    Button(L("settings.shelf.clear", "Empty the shelf"), role: .destructive) {
                        Task { await shelf.removeAll() }
                    }
                    .controlSize(.small)
                    .disabled(shelf.items.isEmpty)
                    Spacer()
                }
                SettingsFootnote(L("settings.shelf.status.help", "A drop copies the file; the original stays where it was. Emptying the shelf removes only the copies."))
            }

            Section(L("settings.shelf.keep", "Retention")) {
                Picker(L("settings.shelf.keep.picker", "Keep copies for"), selection: $store.shelfKeepInterval) {
                    ForEach(ShelfRules.keepIntervalChoices, id: \.self) { seconds in
                        Text(ShelfRules.keepIntervalTitle(seconds)).tag(seconds)
                    }
                }
                SettingsFootnote(L("settings.shelf.keep.help", "Expired copies leave when the shelf loads or takes a drop; nothing runs on a timer. Dragging a file out of the card hands the copy to the other app; Option-tap an item, or its ✕, to remove it."))
            }
        }
    }

    private func countTitle(_ shelf: ShelfStore) -> String {
        switch shelf.items.count {
        case 0: L("settings.shelf.empty", "Nothing on the shelf")
        case 1: L("settings.shelf.count.one", "1 file · \(ShelfRules.formatBytes(shelf.totalBytes))")
        default: L("settings.shelf.count.many", "\(shelf.items.count) files · \(ShelfRules.formatBytes(shelf.totalBytes))")
        }
    }
}
