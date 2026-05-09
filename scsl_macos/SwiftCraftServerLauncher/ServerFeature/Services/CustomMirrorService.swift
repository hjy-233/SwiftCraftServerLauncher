import Foundation

enum CustomMirrorService {
    struct CoreDetail: Hashable {
        let downloadURL: String
        let filename: String
        let sha1: String?
    }

    static func fetchCores(
        config: MirrorCustomAPIConfig,
        baseURL: URL
    ) async throws -> [FastMirrorService.CoreSummary] {
        let response: ScslCoreCLIEnvelope<[FastMirrorService.CoreSummary]> = try await ScslCoreCLIService.shared.runJSON(
            arguments: [
                "mirror", "custom-cores",
                "--config-json", encodeConfig(config),
                "--base-url", baseURL.absoluteString,
            ],
        )
        return response.data
    }

    static func fetchGameVersions(
        config: MirrorCustomAPIConfig,
        baseURL: URL,
        coreName: String
    ) async throws -> [String] {
        let response: ScslCoreCLIEnvelope<[String]> = try await ScslCoreCLIService.shared.runJSON(
            arguments: [
                "mirror", "custom-game-versions",
                "--config-json", encodeConfig(config),
                "--base-url", baseURL.absoluteString,
                "--core-name", coreName,
            ],
        )
        return response.data
    }

    static func fetchCoreVersions(
        config: MirrorCustomAPIConfig,
        baseURL: URL,
        coreName: String,
        gameVersion: String
    ) async throws -> [String] {
        let response: ScslCoreCLIEnvelope<[String]> = try await ScslCoreCLIService.shared.runJSON(
            arguments: [
                "mirror", "custom-core-versions",
                "--config-json", encodeConfig(config),
                "--base-url", baseURL.absoluteString,
                "--core-name", coreName,
                "--game-version", gameVersion,
            ],
        )
        return response.data
    }

    static func fetchCoreDetail(
        config: MirrorCustomAPIConfig,
        baseURL: URL,
        coreName: String,
        gameVersion: String,
        coreVersion: String
    ) async throws -> CoreDetail {
        let response: ScslCoreCLIEnvelope<FastMirrorService.CoreDetail> = try await ScslCoreCLIService.shared.runJSON(
            arguments: [
                "mirror", "custom-detail",
                "--config-json", encodeConfig(config),
                "--base-url", baseURL.absoluteString,
                "--core-name", coreName,
                "--game-version", gameVersion,
                "--core-version", coreVersion,
            ],
        )
        return CoreDetail(
            downloadURL: response.data.downloadURL,
            filename: response.data.filename,
            sha1: response.data.sha1
        )
    }

    private static func encodeConfig(_ config: MirrorCustomAPIConfig) throws -> String {
        let data = try JSONEncoder().encode(config)
        guard let json = String(data: data, encoding: .utf8) else {
            throw GlobalError.network(
                chineseMessage: "镜像服务数据格式不正确",
                i18nKey: "error.network.api_request_failed",
                level: .notification
            )
        }
        return json
    }
}
