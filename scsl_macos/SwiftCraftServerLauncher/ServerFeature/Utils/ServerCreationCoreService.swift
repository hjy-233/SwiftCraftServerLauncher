import Foundation

enum ServerCreationCoreService {
    static func createLocal(request: LocalServerCreateRequest) async throws -> LocalServerCreateResponse {
        let data = try JSONEncoder().encode(request)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ScslCoreCLIError.invalidUTF8
        }
        let response: ScslCoreCLIEnvelope<LocalServerCreateResponse> = try await ScslCoreCLIService.shared.runJSON(
            arguments: ["server", "create-local", "--json", json]
        )
        return response.data
    }
}

struct LocalServerCreateRequest: Encodable {
    let id: String
    let name: String
    let directoryName: String
    let iconName: String
    let iconImageFileName: String?
    let serverType: ServerType
    let gameVersion: String
    let loaderVersion: String
    let launchCommand: String
    let javaPath: String
    let jvmArguments: String
    let xms: Int
    let xmx: Int
    let consoleMode: ServerConsoleMode
    let rconPort: Int
    let rconPassword: String
    let acceptEula: Bool
    let source: LocalServerCreateSource
}

enum LocalServerCreateSource: Encodable {
    case customJar(sourcePath: String)
    case download(url: String, fileName: String, sha1: String?, headers: [String: String]?)

    private enum CodingKeys: String, CodingKey {
        case type
        case sourcePath
        case url
        case fileName
        case sha1
        case headers
    }

    private enum SourceType: String, Encodable {
        case customJar
        case download
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .customJar(let sourcePath):
            try container.encode(SourceType.customJar, forKey: .type)
            try container.encode(sourcePath, forKey: .sourcePath)
        case let .download(url, fileName, sha1, headers):
            try container.encode(SourceType.download, forKey: .type)
            try container.encode(url, forKey: .url)
            try container.encode(fileName, forKey: .fileName)
            try container.encodeIfPresent(sha1, forKey: .sha1)
            try container.encodeIfPresent(headers, forKey: .headers)
        }
    }
}

struct LocalServerCreateResponse: Decodable {
    let id: String
    let directoryName: String
    let serverJar: String
    let javaPath: String
}
