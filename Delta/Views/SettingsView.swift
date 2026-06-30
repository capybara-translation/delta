import SwiftUI

struct SettingsView: View {
    @AppStorage("keepTextOnReopen") private var keepText = true
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var hotKey = HotKeyController.shared.config
    @State private var hotKeyError: String?

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

            Toggle("Enable global hotkey", isOn: Binding(
                get: { hotKey.isEnabled },
                set: { enabled in
                    applyHotKey(HotKeyConfig(keyCode: hotKey.keyCode,
                                             modifiers: hotKey.modifiers,
                                             isEnabled: enabled))
                }
            ))

            LabeledContent("Shortcut") {
                ShortcutRecorder(
                    displayString: hotKey.displayString,
                    isEnabled: hotKey.isEnabled,
                    onCapture: { keyCode, modifiers in
                        applyHotKey(HotKeyConfig(keyCode: keyCode,
                                                 modifiers: modifiers,
                                                 isEnabled: true))
                    },
                    // Pause the live hotkey while recording so it can't intercept
                    // the keys being typed; resume it if recording is cancelled.
                    onRecordingStart: { HotKeyController.shared.suspend() },
                    onCancel: { resumeHotKey() }
                )
                .frame(width: 140)
                .disabled(!hotKey.isEnabled)
            }

            if let hotKeyError {
                Text(hotKeyError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Reset to Default") { applyHotKey(.default) }

            LabeledContent("Version", value: appVersion)
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
            hotKey = HotKeyController.shared.config
        }
    }

    private func applyHotKey(_ config: HotKeyConfig) {
        if HotKeyController.shared.apply(config) {
            hotKeyError = nil
        } else {
            hotKeyError = "This shortcut is already in use."
        }
        // Reflect the controller's actual state (rolled back on failure).
        hotKey = HotKeyController.shared.config
    }

    /// Restore the live hotkey after a cancelled recording. If re-registration
    /// fails (another process grabbed the combo while recording), surface it
    /// rather than leaving the hotkey silently dead.
    private func resumeHotKey() {
        if !HotKeyController.shared.resume() {
            hotKeyError = "Couldn't re-enable the shortcut. Try again."
        }
    }
}
