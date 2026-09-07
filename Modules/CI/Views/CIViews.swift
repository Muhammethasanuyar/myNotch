import SwiftUI

enum CIStyle {
    static let accent = Color(red: 0.95, green: 0.6, blue: 0.35)

    static func color(_ status: CIStatus) -> Color {
        switch status {
        case .running: accent
        case .success: Color(red: 0.36, green: 0.8, blue: 0.5)
        case .warning: .yellow
        case .failure: .red
        case .cancelled, .unknown: .white.opacity(0.5)
        }
    }
}

/// Compact leading wing: a breathing hammer while something builds.
struct CICompactLeading: View {
    @Environment(\.wingContentSize) private var size

    var body: some View {
        PulsingSymbol(systemName: "hammer.fill", pointSize: size * 0.6, weight: .semibold, color: CIStyle.accent, isActive: true)
    }
}

/// Compact trailing wing: how many runs are in flight, or the branch of the one.
struct CICompactTrailing: View {
    let service: CIService
    @Environment(\.wingContentSize) private var size

    var body: some View {
        let running = service.runs.filter(\.isRunning)
        Text(running.count == 1 ? (running[0].subtitle?.split(separator: "·").last.map { String($0).trimmingCharacters(in: .whitespaces) } ?? "1") : String(running.count))
            .font(.system(size: size * 0.45, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .frame(maxWidth: size * 2.4)
    }
}

private enum CIFocus: Hashable {
    case run(String)
    case github
}

/// The card: the last builds on this Mac and the last runs of each repository, newest first.
struct CIExpandedView: View {
    let service: CIService

    @State private var focus: CIFocus?
    @State private var appeared = false

    var body: some View {
        Group {
            if service.runs.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "hammer")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(CIStyle.accent)
                    Text(L("ci.empty", "No builds yet"))
                        .font(.system(size: 12, weight: .semibold))
                    Text(emptyDetail)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .spotlight(CIFocus.github, focus: $focus, accent: CIStyle.accent)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(Array(service.runs.prefix(8).enumerated()), id: \.element.id) { index, run in
                            CIRunRow(run: run)
                                .spotlight(CIFocus.run(run.id), focus: $focus, accent: CIStyle.color(run.status))
                                .reveal(appeared, index: index)
                                .notchTap(isEnabled: run.url != nil) {
                                    if let url = run.url { NSWorkspace.shared.open(url) }
                                }
                        }
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomLeading) {
            if let focus, let text = explanation(for: focus) {
                NotchExplanationBubble(text: text, accent: CIStyle.accent)
                    .padding(.bottom, 2)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: focus)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: service.runs.map(\.id))
        .onAppear { appeared = true; service.setCardVisible(true) }
        .onDisappear { service.setCardVisible(false) }
    }

    private var emptyDetail: String {
        switch service.github.state {
        case .off: L("ci.empty.off", "Xcode builds appear as they finish; add owner/repo in Settings → Builds for GitHub Actions.")
        case .missing: L("ci.empty.missing", "GitHub CLI not found — brew install gh.")
        case .notAuthenticated: L("ci.empty.auth", "Run gh auth login in Terminal for GitHub Actions.")
        case .ready: L("ci.empty.ready", "Watching; nothing has run yet.")
        case .failed(let message): L("ci.empty.failed", "GitHub: \(message)")
        }
    }

    private func explanation(for focus: CIFocus) -> String? {
        switch focus {
        case .github:
            return L("ci.explain.sources", "Xcode builds come from the build-log manifests in DerivedData; GitHub Actions through your own gh tool, at most once a minute while a run is going.")
        case .run(let id):
            guard let run = service.runs.first(where: { $0.id == id }) else { return nil }
            let when = run.finishedAt.map { $0.formatted(.relative(presentation: .named)) }
            let status = CIRules.statusTitle(run.status)
            let timing = when.map { ", \($0)" } ?? ""
            switch run.source {
            case .xcode(let project):
                let counts = CIRules.countsText(run) ?? L("ci.explain.clean", "No errors or warnings counted.")
                return L("ci.explain.xcode", "\(project): \(status)\(timing). \(counts)")
            case .github(let repo):
                return L("ci.explain.github", "\(repo): \(status)\(timing). Tap to open the run on GitHub.")
            }
        }
    }
}

/// One build or run.
struct CIRunRow: View {
    let run: CIRun

    var body: some View {
        HStack(spacing: 10) {
            if run.isRunning {
                PulsingSymbol(systemName: "hammer.fill", pointSize: 14, weight: .semibold, color: CIStyle.accent, isActive: true)
                    .frame(width: 18)
            } else {
                Image(systemName: CIRules.symbolName(run.status))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CIStyle.color(run.status))
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(run.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text([sourceLabel, run.subtitle].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let counts = CIRules.countsText(run) {
                Text(counts)
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(CIStyle.color(run.status))
            }
            if let finished = run.finishedAt {
                Text(finished.formatted(.relative(presentation: .numeric)))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(Rectangle())
    }

    private var sourceLabel: String {
        switch run.source {
        case .xcode: "Xcode"
        case .github(let repo): repo
        }
    }
}
