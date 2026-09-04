import SwiftUI

/// Renders the notch engine in a normal window with its own view model, so states, modules and
/// animation parameters can be exercised without touching the real notch. Separate rows drive the
/// real notch for side-by-side comparison.
struct DebugPreviewView: View {
    let metrics: NotchLayoutMetrics
    let liveModel: NotchViewModel
    let manager: ModuleManager

    @State private var previewModel = NotchViewModel()
    @State private var debugTint = false
    @State private var floatingStyle = false

    var body: some View {
        @Bindable var preview = previewModel
        let previewMetrics = floatingStyle ? metrics.asFloating() : metrics

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ZStack(alignment: .top) {
                    Color(white: 0.82)
                    NotchRootView(
                        model: previewModel,
                        metrics: previewMetrics,
                        content: manager.contentProvider(previewFallback: true),
                        debugTint: debugTint
                    )
                }
                .frame(maxWidth: .infinity)
                .frame(height: metrics.panelSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                stateRow(title: "Preview", model: previewModel)
                stateRow(title: "Real notch", model: liveModel)

                HStack(spacing: 24) {
                    Toggle("Floating style", isOn: $floatingStyle)
                    Toggle("Layout tint", isOn: $debugTint)
                    Toggle("Haptics", isOn: $preview.hapticsEnabled)
                }

                modulesBox
                animationBox(preview: preview)
                metricsGrid
            }
            .padding(20)
        }
        .frame(minWidth: 720, minHeight: 700)
    }

    // MARK: Modules

    private var modulesBox: some View {
        GroupBox("Modules — drives the real notch through the EventBus") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Active module")
                        .foregroundStyle(.secondary)
                    Text(manager.activeModuleID ?? "none")
                        .font(.system(.body, design: .monospaced))
                }
                ForEach(manager.modules, id: \.id) { module in
                    moduleRow(module)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func moduleRow(_ module: any NotchModule) -> some View {
        HStack(spacing: 10) {
            Toggle(module.displayName, isOn: Binding(
                get: { module.isEnabled },
                set: { manager.setEnabled($0, for: module.id) }
            ))
            .frame(width: 110, alignment: .leading)

            Text(String(describing: module.activity))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            if let demo = module as? DemoModule {
                Picker("", selection: Binding(
                    get: { demo.activity },
                    set: { demo.setActivity($0) }
                )) {
                    ForEach(ModuleActivity.allCases, id: \.self) { activity in
                        Text(String(describing: activity)).tag(activity)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)

                Button("Next track") { demo.skipToNextTrack() }
                Button(demo.isPlaying ? "Pause" : "Play") { demo.togglePlayPause() }
            }

            Button("Test popup") {
                manager.bus.post(.popup(NotchEvent(
                    moduleID: module.id,
                    title: "\(module.displayName) event",
                    detail: "Posted from the Debug Preview",
                    symbolName: "bell.fill"
                )))
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Animation

    private func animationBox(preview: NotchViewModel) -> some View {
        GroupBox("Animation playground (preview model)") {
            VStack(alignment: .leading, spacing: 6) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    slider("Open response", value: Binding(get: { preview.animation.openResponse },
                                                           set: { preview.animation.openResponse = $0 }), range: 0.15...0.9)
                    slider("Open damping", value: Binding(get: { preview.animation.openDamping },
                                                          set: { preview.animation.openDamping = $0 }), range: 0.4...1.0)
                    slider("Close response", value: Binding(get: { preview.animation.closeResponse },
                                                            set: { preview.animation.closeResponse = $0 }), range: 0.15...0.9)
                    slider("Close damping", value: Binding(get: { preview.animation.closeDamping },
                                                           set: { preview.animation.closeDamping = $0 }), range: 0.4...1.0)
                    slider("Hover delay", value: Binding(get: { preview.hoverDelay },
                                                         set: { preview.hoverDelay = $0 }), range: 0...1.0)
                    slider("Close delay", value: Binding(get: { preview.closeDelay },
                                                         set: { preview.closeDelay = $0 }), range: 0...3.0)
                }
                HStack {
                    Button("Reset") {
                        previewModel.animation = .default
                        previewModel.hoverDelay = 0.15
                        previewModel.closeDelay = 1.5
                    }
                    Button("Apply to real notch") {
                        liveModel.animation = previewModel.animation
                        liveModel.hoverDelay = previewModel.hoverDelay
                        liveModel.closeDelay = previewModel.closeDelay
                    }
                }
            }
        }
    }

    // MARK: Rows and metrics

    private func stateRow(title: String, model: NotchViewModel) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(width: 84, alignment: .leading)
                .foregroundStyle(.secondary)
            Button("Closed") { model.override(.closed) }
            Button("Compact") { model.override(.compact) }
            Button("Expanded") { model.override(.expanded(moduleID: model.defaultModuleID)) }
            Button("Popup") {
                model.showPopup(NotchEvent(
                    moduleID: model.defaultModuleID,
                    title: "Preview popup",
                    detail: "Forced from the Debug Preview",
                    symbolName: "bell.fill"
                ))
            }
            Text(Self.describe(model.state) + (model.banner == nil ? "" : " + banner"))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var metricsGrid: some View {
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
