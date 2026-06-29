import ServiceManagement

/// Thin wrapper over SMAppService.mainApp for "launch at login".
/// The OS registration status is the source of truth; this app does not persist it separately.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
