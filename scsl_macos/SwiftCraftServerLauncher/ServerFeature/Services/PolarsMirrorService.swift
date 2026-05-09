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
        let response: ScslCoreCLIEnvelope<[CoreType]> = try await ScslCoreCLIService.shared.runJSON(
            arguments: [
                "mirror", "polars-core-types",
                "--base-url", (baseURL ?? Self.baseURL).absoluteString,
            ],
        )
        return response.data
    }

    static func fetchCoreItems(coreTypeId: Int, baseURL: URL? = nil) async throws -> [CoreItem] {
        let response: ScslCoreCLIEnvelope<[CoreItem]> = try await ScslCoreCLIService.shared.runJSON(
            arguments: [
                "mirror", "polars-core-items",
                "--core-type-id", String(coreTypeId),
                "--base-url", (baseURL ?? Self.baseURL).absoluteString,
            ],
        )
        return response.data
    }
}
