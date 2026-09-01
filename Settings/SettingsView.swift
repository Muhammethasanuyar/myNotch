import SwiftUI

/// Placeholder for the Settings window. Real preferences (module toggles, hover delay,
/// thresholds, screen selection, launch at login) arrive in Phase 5.
struct SettingsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gearshape")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Settings arrive in Phase 5.")
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(width: 360, height: 180)
    }
}
