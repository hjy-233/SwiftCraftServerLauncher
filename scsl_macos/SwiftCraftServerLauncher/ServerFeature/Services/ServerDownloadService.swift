import Foundation

enum ServerDownloadService {
    struct DownloadTarget {
        let url: URL
        let sha1: String?
        let fileName: String
        let headers: [String: String]?
    }

    struct MirrorDownloadOptions {
        let source: ServerMirrorSource
        let coreName: String?
        let fileName: String?
        let downloadURL: String?
        let baseURL: String?

        init(
            source: ServerMirrorSource,
            coreName: String? = nil,
            fileName: String? = nil,
            downloadURL: String? = nil,
            baseURL: String? = nil
        ) {
            self.source = source
            self.coreName = coreName
            self.fileName = fileName
            self.downloadURL = downloadURL
            self.baseURL = baseURL
        }
    }

    static func downloadServerJar(
        serverType: ServerType,
        gameVersion: String,
        loaderVersion: String,
        serverDir: URL,
        mirror: MirrorDownloadOptions
    ) async throws -> String {
        let target = try await resolveDownloadTarget(
            serverType: serverType,
            gameVersion: gameVersion,
            loaderVersion: loaderVersion,
            mirror: mirror
        )
        let destinationURL = serverDir.appendingPathComponent(target.fileName)
        _ = try await DownloadManager.downloadFile(
            urlString: target.url.absoluteString,
            destinationURL: destinationURL,
            expectedSha1: target.sha1,
            headers: target.headers
        )
        return target.fileName
    }

    static func resolveDownloadTargetForRemote(
        serverType: ServerType,
        gameVersion: String,
        loaderVersion: String,
        mirror: MirrorDownloadOptions
    ) async throws -> DownloadTarget {
        let request = DownloadTargetCLIRequest(
            serverType: serverType,
            gameVersion: gameVersion,
            loaderVersion: loaderVersion,
            mirrorSource: mirror.source.rawValue,
            coreName: mirror.coreName,
            fileName: mirror.fileName,
            downloadURL: mirror.downloadURL,
            baseURL: mirror.baseURL
        )
        let payload = try JSONEncoder().encode(request)
        guard let json = String(data: payload, encoding: .utf8) else {
            throw GlobalError.validation(
                chineseMessage: "下载目标参数编码失败",
                i18nKey: "error.validation.invalid_download_url",
                level: .notification
            )
        }
        let response: ScslCoreCLIEnvelope<DownloadTargetCLIResponse> = try await ScslCoreCLIService.shared.runJSON(
            arguments: ["server", "download-target", "--json", json]
        )
        guard let url = URL(string: response.data.url) else {
            throw GlobalError.validation(
                chineseMessage: "无效的下载地址",
                i18nKey: "error.validation.invalid_download_url",
                level: .notification
            )
        }
        return DownloadTarget(
            url: url,
            sha1: response.data.sha1,
            fileName: response.data.fileName,
            headers: response.data.headers
        )
    }

    static func resolveDownloadTargetForServer(
        _ server: ServerInstance,
        mirrorSource: ServerMirrorSource = .official
    ) async throws -> DownloadTarget {
        try await resolveDownloadTarget(
            serverType: server.serverType,
            gameVersion: server.gameVersion,
            loaderVersion: server.loaderVersion,
            mirror: MirrorDownloadOptions(source: mirrorSource)
        )
    }

    static func verifyLocalJarIntegrity(server: ServerInstance) async -> Bool {
        do {
            let response: ScslCoreCLIEnvelope<VerifyJarCLIResponse> = try await ScslCoreCLIService.shared.runJSON(
                arguments: ["server", "verify-jar", server.id]
            )
            return response.data.valid
        } catch {
            Logger.shared.warning("core 校验服务端 Jar 失败，按损坏处理: \(error.localizedDescription)")
            return false
        }
    }

    static func fetchAvailableGameVersions(serverType: ServerType, includeSnapshots: Bool) async throws -> [String] {
        let response: ScslCoreCLIEnvelope<[String]> = try await ScslCoreCLIService.shared.runJSON(
            arguments: [
                "server",
                "game-versions",
                "--server-type", serverType.rawValue,
            ] + (includeSnapshots ? ["--include-snapshots"] : [])
        )
        return response.data
    }

    static func fetchAvailableLoaderVersions(serverType: ServerType, gameVersion: String) async throws -> [String] {
        let response: ScslCoreCLIEnvelope<[String]> = try await ScslCoreCLIService.shared.runJSON(
            arguments: [
                "server",
                "loader-versions",
                "--server-type", serverType.rawValue,
                "--game-version", gameVersion,
            ]
        )
        return response.data
    }

    private static func resolveDownloadTarget(
        serverType: ServerType,
        gameVersion: String,
        loaderVersion: String,
        mirror: MirrorDownloadOptions
    ) async throws -> DownloadTarget {
        let request = DownloadTargetCLIRequest(
            serverType: serverType,
            gameVersion: gameVersion,
            loaderVersion: loaderVersion,
            mirrorSource: mirror.source.rawValue,
            coreName: mirror.coreName,
            fileName: mirror.fileName,
            downloadURL: mirror.downloadURL,
            baseURL: mirror.baseURL
        )
        let payload = try JSONEncoder().encode(request)
        guard let json = String(data: payload, encoding: .utf8) else {
            throw GlobalError.validation(
                chineseMessage: "下载目标参数编码失败",
                i18nKey: "error.validation.invalid_download_url",
                level: .notification
            )
        }
        let response: ScslCoreCLIEnvelope<DownloadTargetCLIResponse> = try await ScslCoreCLIService.shared.runJSON(
            arguments: ["server", "download-target", "--json", json]
        )
        guard let url = URL(string: response.data.url) else {
            throw GlobalError.validation(
                chineseMessage: "无效的下载地址",
                i18nKey: "error.validation.invalid_download_url",
                level: .notification
            )
        }
        return DownloadTarget(
            url: url,
            sha1: response.data.sha1,
            fileName: response.data.fileName,
            headers: response.data.headers
        )
    }

    static func resolveJavaVersion(gameVersion: String) async throws -> JavaVersion {
        let response: ScslCoreCLIEnvelope<JavaVersionCLIResponse> = try await ScslCoreCLIService.shared.runJSON(
            arguments: ["server", "java-version", gameVersion]
        )
        return JavaVersion(component: response.data.component, majorVersion: response.data.majorVersion)
    }

    static func latestStableFabricLoaderVersion(gameVersion: String) async throws -> String {
        let response: ScslCoreCLIEnvelope<LatestLoaderCLIResponse> = try await ScslCoreCLIService.shared.runJSON(
            arguments: ["server", "latest-loader", "--server-type", "fabric", "--game-version", gameVersion]
        )
        return response.data.version
    }

    static func latestStableForgeVersion(gameVersion: String) async throws -> String {
        let response: ScslCoreCLIEnvelope<LatestLoaderCLIResponse> = try await ScslCoreCLIService.shared.runJSON(
            arguments: ["server", "latest-loader", "--server-type", "forge", "--game-version", gameVersion]
        )
        return response.data.version
    }
}

private struct DownloadTargetCLIRequest: Encodable {
    let serverType: ServerType
    let gameVersion: String
    let loaderVersion: String
    let mirrorSource: String
    let coreName: String?
    let fileName: String?
    let downloadURL: String?
    let baseURL: String?
}

private struct DownloadTargetCLIResponse: Decodable {
    let url: String
    let sha1: String?
    let fileName: String
    let headers: [String: String]?
}

private struct JavaVersionCLIResponse: Decodable {
    let component: String
    let majorVersion: Int
}

private struct LatestLoaderCLIResponse: Decodable {
    let version: String
}

private struct VerifyJarCLIResponse: Decodable {
    let valid: Bool
}
