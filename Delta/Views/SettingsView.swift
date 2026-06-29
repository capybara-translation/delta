import SwiftUI

struct SettingsView: View {
    @AppStorage("keepTextOnReopen") private var keepText = true

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        Form {
            Toggle("Keep text between launches", isOn: $keepText)
            LabeledContent("Version", value: appVersion)
        }
        .padding(20)
        .frame(width: 360)
    }
}
