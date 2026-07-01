import Testing
import Foundation
@testable import Delta

struct GitHubReleaseTests {
    @Test func decodesTagNameFromGitHubJSON() throws {
        let json = #"{"tag_name":"v1.3.1","name":"v1.3.1","draft":false,"prerelease":false}"#.data(using: .utf8)!
        let release = try JSONDecoder().decode(GitHubRelease.self, from: json)
        #expect(release.tagName == "v1.3.1")
    }
}
