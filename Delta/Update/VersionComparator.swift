import Foundation

/// Compares release version strings. Strips a leading "v"/"V" and compares
/// numerically so that, e.g., 1.10.0 is newer than 1.9.0.
enum VersionComparator {
    /// True if `latestTag` is a strictly newer version than `currentVersion`.
    /// A `latestTag` that isn't version-like (doesn't start with a digit after
    /// stripping "v") is treated as "not newer", so a stray non-numeric tag can't
    /// be reported as an update (numeric comparison would otherwise rank letters
    /// above digits).
    static func isNewer(latestTag: String, currentVersion: String) -> Bool {
        let latest = strip(latestTag)
        guard let first = latest.first, first.isNumber else { return false }
        return latest.compare(strip(currentVersion), options: .numeric) == .orderedDescending
    }

    private static func strip(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if let first = t.first, first == "v" || first == "V" { t.removeFirst() }
        return t
    }
}
