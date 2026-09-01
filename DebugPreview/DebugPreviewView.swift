import SwiftUI

/// Shows the notch root view at true size on a neutral "top of screen" strip, plus the
/// measured layout metrics and debug toggles. Phase 1 adds state overrides and animation sliders.
struct DebugPreviewView: View {
    let metrics: NotchLayoutMetrics
    @State private var debugTint = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .top) {
                Color(white: 0.82)
                NotchRootView(metrics: metrics, debugTint: debugTint)
            }
            .frame(maxWidth: .infinity)
            .frame(height: metrics.panelSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Toggle("Show layout tint (panel footprint red, notch blue)", isOn: $debugTint)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Screen").foregroundStyle(.secondary)
                    Text(metrics.screenName)
                }
                GridRow {
                    Text("Notch").foregroundStyle(.secondary)
                    Text(notchDescription)
                }
                GridRow {
                    Text("Panel").foregroundStyle(.secondary)
                    Text(Self.format(metrics.panelSize))
                }
            }
            .font(.system(.body, design: .monospaced))

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 360)
    }

    private var notchDescription: String {
        metrics.hasNotch
            ? Self.format(metrics.notchSize)
            : "none — fallback \(Self.format(metrics.notchSize))"
    }

    private static func format(_ size: CGSize) -> String {
        "\(Int(size.width.rounded())) × \(Int(size.height.rounded())) pt"
    }
}
