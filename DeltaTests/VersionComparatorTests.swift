import Testing
@testable import Delta

struct VersionComparatorTests {
    @Test func newerPatchIsNewer() {
        #expect(VersionComparator.isNewer(latestTag: "v1.3.1", currentVersion: "1.3.0"))
    }
    @Test func comparesNumericallyNotLexically() {
        #expect(VersionComparator.isNewer(latestTag: "v1.10.0", currentVersion: "1.9.0"))
    }
    @Test func equalIsNotNewer() {
        #expect(!VersionComparator.isNewer(latestTag: "v1.3.0", currentVersion: "1.3.0"))
    }
    @Test func olderIsNotNewer() {
        #expect(!VersionComparator.isNewer(latestTag: "v1.2.0", currentVersion: "1.3.0"))
    }
    @Test func handlesMixedVPrefix() {
        #expect(VersionComparator.isNewer(latestTag: "1.3.1", currentVersion: "v1.3.0"))
    }
    @Test func handlesCapitalVPrefix() {
        #expect(VersionComparator.isNewer(latestTag: "V1.3.1", currentVersion: "1.3.0"))
    }
    @Test func emptyTagIsNotNewer() {
        #expect(!VersionComparator.isNewer(latestTag: "", currentVersion: "1.3.0"))
    }
    @Test func nonNumericTagIsNotNewer() {
        // A non-version-like tag must not be reported as an update (a plain numeric
        // comparison would rank "abc" above "1.3.0").
        #expect(!VersionComparator.isNewer(latestTag: "abc", currentVersion: "1.3.0"))
    }
    @Test func preReleaseStyleTagComparesNumerically() {
        #expect(VersionComparator.isNewer(latestTag: "v2.0.0-rc.1", currentVersion: "1.9.0"))
    }
}
