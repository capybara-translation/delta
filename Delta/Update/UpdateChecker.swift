import AppKit
import Observation

/// Checks GitHub Releases for a newer version. Launch checks update observable
/// state silently; manual checks report the outcome via an alert. Never installs
/// anything — it only points the user at the Releases page.
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    private static let releasesURL = URL(string: "https://github.com/capybara-translation/delta/releases/latest")!
    private static let apiURL = URL(string: "https://api.github.com/repos/capybara-translation/delta/releases/latest")!

    private(set) var latestVersion: String?
    private(set) var isUpdateAvailable = false

    /// Guards against a second manual check starting while one is in flight
    /// (rapid double-clicks would otherwise stack alerts).
    @ObservationIgnored private var isChecking = false

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private init() {}

    /// Called at launch. Runs only when the "check on launch" preference is on
    /// (missing key defaults to true). Failures are silent.
    func checkOnLaunch() {
        let enabled = UserDefaults.standard.object(forKey: "checkForUpdatesOnLaunch") as? Bool ?? true
        guard enabled else { return }
        Task { try? await refresh() }
    }

    /// Manual check from the menu. Always runs; always reports via an alert.
    /// Ignores re-entry while a check is already in flight.
    func checkManually() {
        guard !isChecking else { return }
        isChecking = true
        Task {
            defer { isChecking = false }
            do {
                try await refresh()
                if isUpdateAvailable, let latest = latestVersion {
                    showUpdateAlert(latest: latest)
                } else {
                    showUpToDateAlert()
                }
            } catch {
                showErrorAlert()
            }
        }
    }

    func openReleasesPage() {
        NSWorkspace.shared.open(Self.releasesURL)
    }

    /// Fetches the latest release, decodes it, and updates state. Throws on failure.
    private func refresh() async throws {
        var request = URLRequest(url: Self.apiURL)
        request.timeoutInterval = 10   // don't leave a manual check hanging on a bad network
        request.setValue("Delta-Diff", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        latestVersion = release.tagName
        isUpdateAvailable = VersionComparator.isNewer(latestTag: release.tagName, currentVersion: currentVersion)
    }

    private func showUpdateAlert(latest: String) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Update available"
        alert.informativeText = "A new version (\(latest)) is available."
        alert.addButton(withTitle: "Open Releases")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            openReleasesPage()
        }
    }

    private func showUpToDateAlert() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "You're up to date"
        alert.informativeText = "Delta Diff \(currentVersion) is the latest version."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showErrorAlert() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Couldn't check for updates"
        alert.informativeText = "Please try again later."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
