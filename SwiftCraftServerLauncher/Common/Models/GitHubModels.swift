import Foundation

// MARK: - GitHub Contributor Model
public struct GitHubContributor: Codable, Identifiable {
    public let id: Int
    public let login: String
    public let avatarUrl: String
    public let htmlUrl: String
    public let contributions: Int

    enum CodingKeys: String, CodingKey {
        case id
        case login
        case avatarUrl = "avatar_url"
        case htmlUrl = "html_url"
        case contributions
    }
}

// MARK: - GitHub Release Model
public struct GitHubRelease: Codable, Identifiable, Hashable {
    public let id: Int
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlUrl: String
    public let publishedAt: String?
    public let prerelease: Bool
    public let draft: Bool
    public let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case id
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
        case prerelease
        case draft
        case assets
    }
}

public struct GitHubReleaseAsset: Codable, Hashable {
    public let name: String
    public let size: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case size
    }
}
