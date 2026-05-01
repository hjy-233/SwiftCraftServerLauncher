import Foundation

enum PolarsMirrorService {
    struct CoreType: Decodable, Hashable, Identifiable {
        let id: Int
        let name: String
        let description: String?
    }

    struct CoreItem: Decodable, Hashable {
        let name: String
        let downloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "downloadUrl"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            let rawURL = try container.decode(String.self, forKey: .downloadURL)
            if rawURL.lowercased().hasPrefix("http://") {
                downloadURL = "https://" + rawURL.dropFirst("http://".count)
            } else {
                downloadURL = rawURL
            }
        }
    }

    private static let baseURL = URL(string: "https://mirror.polars.cc/api/query/minecraft/core") ?? URL(fileURLWithPath: "/")

    static func fetchCoreTypes(baseURL: URL? = nil) async throws -> [CoreType] {
        let resolvedBaseURL = baseURL ?? Self.baseURL
        let data = try await APIClient.get(url: resolvedBaseURL)
        return try JSONDecoder().decode([CoreType].self, from: data)
    }

    static func fetchCoreItems(coreTypeId: Int, baseURL: URL? = nil) async throws -> [CoreItem] {
        let resolvedBaseURL = baseURL ?? Self.baseURL
        let url = resolvedBaseURL.appendingPathComponent("\(coreTypeId)")
        let data = try await APIClient.get(url: url)
        return try JSONDecoder().decode([CoreItem].self, from: data)
    }
}
