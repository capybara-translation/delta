import SwiftUI

struct SettingsView: View {
    @AppStorage("keepTextOnReopen") private var keepText = true
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        Form {
            Toggle("Keep text between launches", isOn: $keepText)

            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    try? LaunchAtLogin.setEnabled(newValue)
                    // Reflect the real OS status (reverts the toggle if it failed).
                    launchAtLogin = LaunchAtLogin.isEnabled
                }
            ))

            LabeledContent("Version", value: appVersion)
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }
}
