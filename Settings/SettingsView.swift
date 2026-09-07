import SwiftUI

/// Sidebar + detail, with back/forward history in the toolbar like System Settings.
struct SettingsView: View {
    let context: SettingsContext
    @Bindable var navigation: SettingsNavigation
    let closeWindow: @MainActor () -> Void

    @State private var history: [SettingsTab] = [.general]
    @State private var historyIndex = 0
    @State private var isTravelling = false

    private var activeTab: SettingsTab {
        navigation.selectedTab ?? .general
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebar
        } detail: {
            pane(for: activeTab)
                .navigationTitle(activeTab.title)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 640, minHeight: 480)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { travel(by: -1) } label: { Image(systemName: "chevron.left") }
                    .disabled(historyIndex == 0)
                    .help(L("settings.nav.back", "Back"))
                Button { travel(by: 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(historyIndex >= history.count - 1)
                    .help(L("settings.nav.forward", "Forward"))
            }
        }
        .onChange(of: navigation.selectedTab) { _, tab in
            record(tab)
        }
    }

    private var sidebar: some View {
        List(selection: $navigation.selectedTab) {
            ForEach(SettingsTab.allCases) { tab in
                Label(tab.title, systemImage: tab.symbolName)
                    .tag(tab)
            }
        }
        .listStyle(.sidebar)
        .softScrollEdges()
        .navigationSplitViewColumnWidth(min: 190, ideal: 190, max: 190)
        .toolbar(removing: .sidebarToggle)
        .safeAreaInset(edge: .bottom) {
            Text(AppVersion.display)
                .font(.footnote)
                .fontDesign(.monospaced)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func pane(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            GeneralPane(store: context.store, launchAtLogin: context.launchAtLogin)
        case .modules:
            ModulesPane(store: context.store, manager: context.manager)
        case .media:
            MediaPane(store: context.store, module: context.media)
        case .claude:
            ClaudePane(store: context.store, module: context.claude)
        case .calendar:
            CalendarPane(store: context.store, module: context.calendar)
        case .battery:
            BatteryPane(store: context.store, module: context.battery)
        case .pomodoro:
            PomodoroPane(store: context.store, module: context.pomodoro)
        case .shelf:
            ShelfPane(store: context.store, module: context.shelf)
        case .downloads:
            DownloadsPane(store: context.store, module: context.downloads)
        case .ci:
            CIPane(store: context.store, module: context.ci)
        case .sound:
            SoundPane(store: context.store, volume: context.volume, audioDevice: context.audioDevice)
        case .setup:
            SetupPane(context: context, navigation: navigation, closeWindow: closeWindow)
        case .about:
            AboutPane(openDebugPreview: context.openDebugPreview, checkForUpdates: context.checkForUpdates)
        }
    }

    // MARK: History

    private func record(_ tab: SettingsTab?) {
        guard !isTravelling, let tab, history[historyIndex] != tab else { return }
        history = Array(history.prefix(historyIndex + 1)) + [tab]
        historyIndex = history.count - 1
    }

    private func travel(by offset: Int) {
        let target = historyIndex + offset
        guard history.indices.contains(target) else { return }
        isTravelling = true
        historyIndex = target
        navigation.selectedTab = history[target]
        isTravelling = false
    }
}

/// Version line for the sidebar footer and the About pane.
nonisolated enum AppVersion {
    static var display: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }
}

extension View {
    /// macOS 26's progressive blur at the scroll edges; a no-op before it.
    @ViewBuilder
    func softScrollEdges() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self
        }
    }
}
