import SwiftUI

/// Where downloads are watched, whether the folder may be read, and how many recent ones stay.
struct DownloadsPane: View {
    @Bindable var store: SettingsStore
    let module: DownloadsModule?

    var body: some View {
        if let module {
            content(module)
        } else {
            ContentUnavailableView(L("settings.downloads.missing", "The downloads module is not registered."), systemImage: "arrow.down.circle")
        }
    }

    private func content(_ module: DownloadsModule) -> some View {
        SettingsForm {
            Section(L("settings.downloads.access", "Folder")) {
                if !store.isModuleEnabled(module.id) {
                    StatusRow(tone: .neutral, title: L("settings.downloads.off", "Off"), detail: L("settings.downloads.off.help", "Turn the module on under Modules; the folder is not touched until then."))
                } else {
                    accessStatus(module.service)
                }
                TextField(L("settings.downloads.folder", "Folder"), text: $store.downloadsFolder, prompt: Text(DownloadsService.defaultFolder.path(percentEncoded: false)))
                    .textFieldStyle(.roundedBorder)
                SettingsFootnote(L("settings.downloads.folder.help", "Empty means your Downloads folder. Reading it is what macOS asks permission for; the grant is tied to the app's signature, so a rebuilt app asks again. Only file names and sizes are read, nothing leaves this Mac."))
            }

            Section(L("settings.downloads.behaviour", "Behaviour")) {
                Toggle(L("settings.downloads.popups", "Popup when a download finishes"), isOn: $store.downloadsCompletionPopups)
                    .toggleStyle(.switch)
                ValueSlider(
                    title: L("settings.downloads.keep", "Recent downloads on the card"),
                    value: Binding(get: { Double(store.downloadsKeepRecent) }, set: { store.downloadsKeepRecent = Int($0.rounded()) }),
                    range: Double(SettingsRules.downloadsKeepRange.lowerBound)...Double(SettingsRules.downloadsKeepRange.upperBound),
                    step: 1,
                    format: { String(Int($0)) }
                )
                SettingsFootnote(L("settings.downloads.behaviour.help", "Safari says how big a file will be, so its bar is exact; Chrome, Edge and Brave do not, so theirs just moves. A finished file can go to the shelf from the card."))
            }
        }
    }

    @ViewBuilder
    private func accessStatus(_ service: DownloadsService) -> some View {
        switch service.access {
        case .unknown:
            StatusRow(tone: .pending, title: L("settings.downloads.checking", "Checking the folder…"))
        case .granted:
            StatusRow(tone: .ok, title: L("settings.downloads.granted", "Watching"), detail: service.folder.path(percentEncoded: false))
        case .denied:
            StatusRow(tone: .problem, title: L("settings.downloads.denied", "macOS did not allow reading this folder"), detail: service.folder.path(percentEncoded: false))
            HStack(spacing: 8) {
                Button(L("settings.downloads.retry", "Try again")) { service.requestAccess() }
                    .controlSize(.small)
                Button(L("settings.downloads.openPrivacy", "Open Privacy Settings…")) { SystemSettingsLink.open(SystemSettingsLink.filesAndFolders) }
                    .controlSize(.small)
                Spacer()
            }
        }
    }
}
