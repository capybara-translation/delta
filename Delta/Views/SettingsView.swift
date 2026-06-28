import SwiftUI

struct SettingsView: View {
    @AppStorage("keepTextOnReopen") private var keepText = true

    var body: some View {
        Form {
            Toggle("Keep text between launches", isOn: $keepText)
        }
        .padding(20)
        .frame(width: 360)
    }
}
