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
}
