import SwiftUI

/// Renders the engine in a normal window with a private view model, so states, hover and
/// animation parameters can be exercised without touching the real notch. A second row of
/// buttons drives the real notch for side-by-side checks.
struct DebugPreviewView: View {
    let metrics: NotchLayoutMetrics
    let liveModel: NotchViewModel

    @State private var previewModel = NotchViewModel()
    @State private var debugTint = false
    @State private var floatingStyle = false
    private let content = FakeNotchContent.provider()

    var body: some View {
        @Bindable var preview = previewModel
        let previewMetrics = floatingStyle ? metrics.asFloating() : metrics

        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .top) {
                Color(white: 0.82)
                NotchRootView(model: previewModel, metrics: previewMetrics, content: content, debugTint: debugTint)
            }
            .frame(maxWidth: .infinity)
            .frame(height: metrics.panelSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            stateRow(title: "Preview", model: previewModel)
            stateRow(title: "Real notch", model: liveModel)

            HStack(spacing: 24) {
                Toggle("Floating style (no housing)", isOn: $floatingStyle)
                Toggle("Layout tint", isOn: $debugTint)
                Toggle("Haptics", isOn: $preview.hapticsEnabled)
            }

            GroupBox("Animation playground (preview model)") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    slider("Open response", value: $preview.animation.openResponse, range: 0.15...0.9)
                    slider("Open damping", value: $preview.animation.openDamping, range: 0.4...1.0)
                    slider("Close response", value: $preview.animation.closeResponse, range: 0.15...0.9)
                    slider("Close damping", value: $preview.animation.closeDamping, range: 0.4...1.0)
                    slider("Hover delay", value: $preview.hoverDelay, range: 0...1.0)
                }
                HStack {
                    Button("Reset") {
                        previewModel.animation = .default
                        previewModel.hoverDelay = 0.15
                    }
                    Button("Apply to real notch") {
                        liveModel.animation = previewModel.animation
                        liveModel.hoverDelay = previewModel.hoverDelay
                    }
                }
                .padding(.top, 4)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("Screen").foregroundStyle(.secondary)
                    Text(metrics.screenName)
                }
                GridRow {
                    Text("Style").foregroundStyle(.secondary)
                    Text(metrics.style == .notch ? "notch" : "floating")
                }
                GridRow {
                    Text("Notch").foregroundStyle(.secondary)
                    Text(Self.format(metrics.notchSize))
                }
                GridRow {
                    Text("Menu bar").foregroundStyle(.secondary)
                    Text("\(Int(metrics.menuBarHeight.rounded())) pt")
                }
                GridRow {
                    Text("Panel").foregroundStyle(.secondary)
                    Text(Self.format(metrics.panelSize))
                }
            }
            .font(.system(.caption, design: .monospaced))

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 700, minHeight: 620)
    }

    private func stateRow(title: String, model: NotchViewModel) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(width: 84, alignment: .leading)
                .foregroundStyle(.secondary)
            Button("Closed") { model.override(.closed) }
            Button("Compact") { model.override(.compact) }
            Button("Expanded") { model.override(.expanded(moduleID: FakeNotchContent.moduleID)) }
            Button("Popup") { model.showPopup(FakeNotchContent.sampleEvent()) }
            Text(Self.describe(model.state) + (model.banner == nil ? "" : " + banner"))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        GridRow {
            Text(title).frame(width: 110, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 40, alignment: .trailing)
        }
    }

    private static func describe(_ state: NotchState) -> String {
        switch state {
        case .closed: return "closed"
        case .compact: return "compact"
        case .expanded(let moduleID): return "expanded(\(moduleID))"
        case .popup(let event): return "popup(\(event.title))"
        }
    }

    private static func format(_ size: CGSize) -> String {
        "\(Int(size.width.rounded())) × \(Int(size.height.rounded())) pt"
    }
}
