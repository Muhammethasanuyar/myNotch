import AppKit
import SwiftUI

/// A grouped, transparent form: the three modifiers every pane needs so the window chrome shows through.
struct SettingsForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }
}

/// How a status row reads at a glance.
nonisolated enum StatusTone: Sendable {
    case ok
    case attention
    case problem
    case pending
    case neutral

    var color: Color {
        switch self {
        case .ok: .green
        case .attention: .orange
        case .problem: .red
        case .pending: .blue
        case .neutral: .secondary
        }
    }

    var symbolName: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .problem: "xmark.octagon.fill"
        case .pending: "clock.fill"
        case .neutral: "circle.dashed"
        }
    }
}

/// One line of state: coloured symbol, title, optional detail.
struct StatusRow: View {
    let tone: StatusTone
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: tone.symbolName)
                .foregroundStyle(tone.color)
                .font(.body)
                .frame(width: 20)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .animation(.default, value: tone.symbolName)
    }
}

/// Small grey explanation under a control.
struct SettingsFootnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Slider with the value spelled out beside it.
struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 12) {
                Slider(value: $value, in: range, step: step)
                    .frame(width: 180)
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .trailing)
                    .contentTransition(.numericText())
                    .animation(.default, value: value)
            }
        }
    }
}

/// Number formats the sliders share.
nonisolated enum SettingsFormat {
    static func seconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2))) + " s"
    }

    static func signedMilliseconds(_ value: Double) -> String {
        let ms = Int((value * 1000).rounded())
        return (ms > 0 ? "+" : "") + ms.formatted() + " ms"
    }

    static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    static func minutes(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.minutes], width: .abbreviated))
    }
}

/// Puts a string on the clipboard and confirms briefly.
struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .help(L("settings.copy", "Copy"))
    }
}

/// Monospaced, selectable text with a copy button — for commands and URIs.
struct CopyableText: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            CopyButton(text: text)
        }
    }
}

/// Opens a System Settings pane by its URL scheme.
nonisolated enum SystemSettingsLink {
    static let automation = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

    @MainActor
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
