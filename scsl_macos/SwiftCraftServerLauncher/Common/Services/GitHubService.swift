import Foundation

// MARK: - GitHub Service
@MainActor
public class GitHubService: ObservableObject {

    public static let shared = GitHubService()

    // MARK: - Public Methods

    private func fetchJSON<T: Decodable>(
        url: URL,
        headers: [String: String] = [:]
    ) async throws -> T {
        let headersJSON = headers.isEmpty ? nil : String(
            data: try JSONSerialization.data(withJSONObject: headers),
            encoding: .utf8
        )
        let payload = try await ScslCoreCLIService.shared.run(
            arguments: {
                var arguments = ["game", "fetch-json", "--url", url.absoluteString]
                if let headersJSON {
                    arguments.append(contentsOf: ["--headers-json", headersJSON])
                }
                return arguments
            }()
        )
        let data = Data(payload.utf8)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// 获取仓库贡献者列表
    public func fetchContributors(perPage: Int = 50) async throws -> [GitHubContributor] {
        let url = URLConfig.API.GitHub.contributors(perPage: perPage)
        return try await fetchJSON(url: url)
    }

    /// 获取 GitHub Releases 作为版本历史数据。
    public func fetchReleases(perPage: Int = 20) async throws -> [GitHubRelease] {
        let url = URLConfig.API.GitHub.releases(perPage: perPage)
        let headers = ["Accept": "application/vnd.github+json"]
        return try await fetchJSON(url: url, headers: headers)
    }

    // MARK: - Static Contributors

    /// 获取静态贡献者原始数据（JSON）
    private func fetchStaticContributorsData() async throws -> Data {
        let url = URLConfig.API.GitHub.staticContributors()
        let payload = try await ScslCoreCLIService.shared.run(
            arguments: ["game", "fetch-json", "--url", url.absoluteString]
        )
        return Data(payload.utf8)
    }

    /// 获取静态贡献者解码后的数据
    public func fetchStaticContributors<T: Decodable>() async throws -> T {
        let data = try await fetchStaticContributorsData()
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Acknowledgements

    /// 获取开源致谢原始数据（JSON）
    private func fetchAcknowledgementsData() async throws -> Data {
        let url = URLConfig.API.GitHub.acknowledgements()
        let headers = ["Accept": "application/json"]
        let payload = try await ScslCoreCLIService.shared.run(
            arguments: [
                "game", "fetch-json",
                "--url", url.absoluteString,
                "--headers-json", String(
                    data: try JSONSerialization.data(withJSONObject: headers),
                    encoding: .utf8
                ) ?? "{}",
            ]
        )
        return Data(payload.utf8)
    }

    /// 获取开源致谢解码后的数据
    public func fetchAcknowledgements<T: Decodable>() async throws -> T {
        let data = try await fetchAcknowledgementsData()
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Announcement

    /// 获取公告数据
    /// - Parameters:
    ///   - version: 应用版本号
    ///   - language: 语言代码
    /// - Returns: 公告数据，如果不存在（404）则返回 nil
    public func fetchAnnouncement(
        version: String,
        language: String
    ) async throws -> AnnouncementData? {
        let url = URLConfig.API.GitHub.announcement(
            version: version,
            language: language
        )

        let headers = ["Accept": "application/json"]
        let announcementResponse: AnnouncementResponse = try await fetchJSON(
            url: url,
            headers: headers
        )

        guard announcementResponse.success else {
            throw GitHubServiceError.announcementNotSuccessful
        }

        return announcementResponse.data
    }
}

// MARK: - GitHubService Error

public enum GitHubServiceError: Error {
    case httpError(statusCode: Int)
    case invalidResponse
    case announcementNotSuccessful
}
