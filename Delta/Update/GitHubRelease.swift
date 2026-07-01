/// The subset of a GitHub release we care about (its tag, e.g. "v1.3.1").
struct GitHubRelease: Decodable {
    let tagName: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
    }
}
