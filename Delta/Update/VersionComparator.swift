import Foundation

/// Compares release version strings. Strips a leading "v"/"V" and compares
/// numerically so that, e.g., 1.10.0 is newer than 1.9.0.
enum VersionComparator {
    /// True if `latestTag` is a strictly newer version than `currentVersion`.
    static func isNewer(latestTag: String, currentVersion: String) -> Bool {
        strip(latestTag).compare(strip(currentVersion), options: .numeric) == .orderedDescending
    }

    private static func strip(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if let first = t.first, first == "v" || first == "V" { t.removeFirst() }
        return t
    }
}
