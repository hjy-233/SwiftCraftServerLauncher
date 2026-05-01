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
        let info: CoreInfo = try await requestData(pathComponents: [coreName], baseURL: baseURL)
        return info.mcVersions
    }

    static func fetchCores(baseURL: URL? = nil) async throws -> [CoreSummary] {
        let list: [CoreSummary] = try await requestData(pathComponents: [], baseURL: baseURL)
        return list
    }

    static func fetchCoreVersions(coreName: String, gameVersion: String, baseURL: URL? = nil) async throws -> [String] {
        let list: BuildList = try await requestData(
            pathComponents: [coreName, gameVersion],
            queryItems: [
                URLQueryItem(name: "offset", value: "0"),
                URLQueryItem(name: "limit", value: "25"),
            ],
            baseURL: baseURL
        )
        let versions = list.builds.map { $0.coreVersion }
        var seen: Set<String> = []
        var unique: [String] = []
        for version in versions where !seen.contains(version) {
            seen.insert(version)
            unique.append(version)
        }
        return unique
    }

    static func fetchCoreDetail(
        coreName: String,
        gameVersion: String,
        coreVersion: String,
        baseURL: URL? = nil
    ) async throws -> CoreDetail {
        return try await requestData(
            pathComponents: [coreName, gameVersion, coreVersion],
            baseURL: baseURL
        )
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

    private static func requestData<T: Decodable>(
        pathComponents: [String],
        queryItems: [URLQueryItem] = [],
        baseURL: URL? = nil
    ) async throws -> T {
        let url = buildURL(pathComponents: pathComponents, queryItems: queryItems, baseURL: baseURL)
        let data = try await APIClient.get(url: url, headers: ["Accept": "application/json"])
        if let wrapped = try? JSONDecoder().decode(Response<T>.self, from: data) {
            guard wrapped.success, let payload = wrapped.data else {
                throw GlobalError.network(
                    chineseMessage: wrapped.message ?? "镜像服务不可用",
                    i18nKey: "error.network.api_request_failed",
                    level: .notification
                )
            }
            return payload
        }
        if let direct = try? JSONDecoder().decode(T.self, from: data) {
            return direct
        }
        throw GlobalError.network(
            chineseMessage: "镜像服务数据格式不正确",
            i18nKey: "error.network.api_request_failed",
            level: .notification
        )
    }

    private static func buildURL(pathComponents: [String], queryItems: [URLQueryItem], baseURL: URL?) -> URL {
        let resolvedBase = normalizeBaseURL(baseURL ?? Self.baseURL)
        let base = pathComponents.reduce(resolvedBase) { partial, component in
            partial.appendingPathComponent(component)
        }
        guard !queryItems.isEmpty,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return base
        }
        components.queryItems = queryItems
        return components.url ?? base
    }

    private static func normalizeBaseURL(_ url: URL) -> URL {
        let path = url.path.lowercased()
        if path.contains("/api/v3") {
            return url
        }
        return url.appendingPathComponent("api/v3")
    }
}
