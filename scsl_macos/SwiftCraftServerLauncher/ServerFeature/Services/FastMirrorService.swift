import Foundation

enum FastMirrorService {
    struct CoreSummary: Decodable, Hashable {
        let name: String
        let tag: String?
        let recommend: Bool
        let homepage: String?
        let mcVersions: [String]?

        enum CodingKeys: String, CodingKey {
            case name
            case tag
            case recommend
            case homepage
            case mcVersions = "mc_versions"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            tag = try container.decodeIfPresent(String.self, forKey: .tag)
            recommend = try container.decodeIfPresent(Bool.self, forKey: .recommend) ?? false
            homepage = try container.decodeIfPresent(String.self, forKey: .homepage)
            mcVersions = try container.decodeIfPresent([String].self, forKey: .mcVersions)
        }

        init(
            name: String,
            tag: String?,
            recommend: Bool,
            homepage: String?,
            mcVersions: [String]?
        ) {
            self.name = name
            self.tag = tag
            self.recommend = recommend
            self.homepage = homepage
            self.mcVersions = mcVersions
        }
    }

    struct CoreInfo: Decodable {
        let name: String
        let tag: String?
        let homepage: String?
        let mcVersions: [String]

        enum CodingKeys: String, CodingKey {
            case name
            case tag
            case homepage
            case mcVersions = "mc_versions"
        }
    }

    struct BuildInfo: Decodable, Hashable {
        let name: String
        let mcVersion: String
        let coreVersion: String
        let updateTime: String?
        let sha1: String?

        enum CodingKeys: String, CodingKey {
            case name
            case mcVersion = "mc_version"
            case coreVersion = "core_version"
            case updateTime = "update_time"
            case sha1
        }
    }

    struct BuildList: Decodable {
        let builds: [BuildInfo]
    }

    struct CoreDetail: Decodable {
        let name: String
        let mcVersion: String
        let coreVersion: String
        let updateTime: String?
        let sha1: String?
        let filename: String
        let downloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case mcVersion = "mc_version"
            case coreVersion = "core_version"
            case updateTime = "update_time"
            case sha1
            case filename
            case downloadURL = "download_url"
        }
    }

    struct Response<T: Decodable>: Decodable {
        let data: T?
        let code: String?
        let success: Bool
        let message: String?

        enum CodingKeys: String, CodingKey {
            case data
            case code
            case success
            case message
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            data = try container.decodeIfPresent(T.self, forKey: .data)
            code = try container.decodeIfPresent(String.self, forKey: .code)
            message = try container.decodeIfPresent(String.self, forKey: .message)
            success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? true
        }
    }

    private static let baseURL = URL(string: "https://download.fastmirror.net/api/v3") ?? URL(fileURLWithPath: "/")

    static func fetchGameVersions(coreName: String, baseURL: URL? = nil) async throws -> [String] {
        let response: ScslCoreCLIEnvelope<[String]> = try await ScslCoreCLIService.shared.runJSON(
            arguments: [
                "mirror", "fastmirror-game-versions",
                "--core-name", coreName,
                "--base-url", resolvedBaseURL(baseURL),
            ],
        )
        return response.data
    }

    static func fetchCores(baseURL: URL? = nil) async throws -> [CoreSummary] {
        let response: ScslCoreCLIEnvelope<[CoreSummary]> = try await ScslCoreCLIService.shared.runJSON(
            arguments: [
                "mirror", "fastmirror-cores",
                "--base-url", resolvedBaseURL(baseURL),
            ],
        )
        return response.data
    }

    static func fetchCoreVersions(coreName: String, gameVersion: String, baseURL: URL? = nil) async throws -> [String] {
        let response: ScslCoreCLIEnvelope<[String]> = try await ScslCoreCLIService.shared.runJSON(
            arguments: [
                "mirror", "fastmirror-core-versions",
                "--core-name", coreName,
                "--game-version", gameVersion,
                "--base-url", resolvedBaseURL(baseURL),
            ],
        )
        return response.data
    }

    static func fetchCoreDetail(
        coreName: String,
        gameVersion: String,
        coreVersion: String,
        baseURL: URL? = nil
    ) async throws -> CoreDetail {
        let response: ScslCoreCLIEnvelope<CoreDetail> = try await ScslCoreCLIService.shared.runJSON(
            arguments: [
                "mirror", "fastmirror-detail",
                "--core-name", coreName,
                "--game-version", gameVersion,
                "--core-version", coreVersion,
                "--base-url", resolvedBaseURL(baseURL),
            ],
        )
        return response.data
    }

    static func coreName(for serverType: ServerType) -> String {
        switch serverType {
        case .vanilla:
            return "Vanilla"
        case .paper:
            return "Paper"
        case .fabric:
            return "Fabric"
        case .forge:
            return "Forge"
        case .custom:
            return "Custom"
        }
    }

    static func serverType(for coreName: String) -> ServerType? {
        switch coreName.lowercased() {
        case "vanilla":
            return .vanilla
        case "paper":
            return .paper
        case "fabric":
            return .fabric
        case "forge":
            return .forge
        default:
            return nil
        }
    }

    private static func normalizeBaseURL(_ url: URL) -> URL {
        let path = url.path.lowercased()
        if path.contains("/api/v3") {
            return url
        }
        return url.appendingPathComponent("api/v3")
    }

    private static func resolvedBaseURL(_ url: URL?) -> String {
        normalizeBaseURL(url ?? Self.baseURL).absoluteString
    }
}
