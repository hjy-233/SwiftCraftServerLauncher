import Foundation
import CommonCrypto

enum DownloadManager {
    enum ResourceType: String {
        case mod, datapack, shader, resourcepack

        var folderName: String {
            switch self {
            case .mod: return AppConstants.DirectoryNames.mods
            case .datapack: return AppConstants.DirectoryNames.datapacks
            case .shader: return AppConstants.DirectoryNames.shaderpacks
            case .resourcepack: return AppConstants.DirectoryNames.resourcepacks
            }
        }

        init?(from string: String) {
            // 优化：使用 caseInsensitiveCompare 避免创建临时小写字符串
            let lowercased = string.lowercased()
            switch lowercased {
            case "mod": self = .mod
            case "datapack": self = .datapack
            case "shader": self = .shader
            case "resourcepack": self = .resourcepack
            default: return nil
            }
        }
    }

    /// 下载资源文件
    /// - Parameters:
    ///   - game: 游戏信息
    ///   - urlString: 下载地址
    ///   - resourceType: 资源类型（如 "mod", "datapack", "shader", "resourcepack"）
    ///   - expectedSha1: 预期 SHA1 值
    /// - Returns: 下载到的本地文件 URL
    /// - Throws: GlobalError 当操作失败时
    static func downloadResource(for game: GameVersionInfo, urlString: String, resourceType: String, expectedSha1: String? = nil) async throws -> URL {
        guard let url = URL(string: urlString) else {
            throw GlobalError.validation(
                chineseMessage: "无效的下载地址",
                i18nKey: "error.validation.invalid_download_url",
                level: .notification
            )
        }

        guard let type = ResourceType(from: resourceType) else {
            throw GlobalError.resource(
                chineseMessage: "未知的资源类型",
                i18nKey: "error.resource.unknown_type",
                level: .notification
            )
        }
        let fileName = url.lastPathComponent
        guard !fileName.isEmpty else {
            throw GlobalError.validation(
                chineseMessage: "下载地址缺少文件名",
                i18nKey: "error.validation.invalid_download_url",
                level: .notification
            )
        }

        var arguments = [
            "resource", "download",
            "--game-name", game.gameName,
            "--resource-type", type.rawValue,
            "--url", urlString,
            "--file-name", fileName,
        ]
        if let expectedSha1, !expectedSha1.isEmpty {
            arguments.append(contentsOf: ["--sha1", expectedSha1])
        }

        let response: ScslCoreCLIEnvelope<ResourceDownloadCLIResponse> = try await ScslCoreCLIService.shared.runJSON(
            arguments: arguments
        )
        let resolvedPath = response.data.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedPath.isEmpty else {
            throw GlobalError.resource(
                chineseMessage: "core 未返回下载后的资源路径",
                i18nKey: "error.resource.directory_not_found",
                level: .notification
            )
        }
        return URL(fileURLWithPath: resolvedPath)
    }

    // 常量字符串，避免重复创建
    private static let githubPrefix = "https://github.com/"
    private static let rawGithubPrefix = "https://raw.githubusercontent.com/"
    private static let githubHost = "github.com"
    private static let rawGithubHost = "raw.githubusercontent.com"

    private struct ResourceDownloadCLIResponse: Decodable {
        let path: String
    }

    private struct GenericDownloadCLIResponse: Decodable {
        let path: String
    }

    private static func persistTemporaryFile(_ url: URL) throws -> URL {
        let fileManager = FileManager.default
        let ext = url.pathExtension
        let fileName = "scsl-download-\(UUID().uuidString)" + (ext.isEmpty ? "" : ".\(ext)")
        let destination = fileManager.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try fileManager.moveItem(at: url, to: destination)
            return destination
        } catch {
            try fileManager.copyItem(at: url, to: destination)
            return destination
        }
    }

    /// 通用下载文件到指定路径（不做任何目录结构拼接）
    /// - Parameters:
    ///   - urlString: 下载地址（字符串形式）
    ///   - destinationURL: 目标文件路径
    ///   - expectedSha1: 预期 SHA1 值
    /// - Returns: 下载到的本地文件 URL
    /// - Throws: GlobalError 当操作失败时
    static func downloadFile(
        urlString: String,
        destinationURL: URL,
        expectedSha1: String? = nil
    ) async throws -> URL {
        // 优化：先创建 URL，然后调用内部方法
        let url: URL = try autoreleasepool {
            guard let url = URL(string: urlString) else {
                throw GlobalError.validation(
                    chineseMessage: "无效的下载地址",
                    i18nKey: "error.validation.invalid_download_url",
                    level: .notification
                )
            }
            return url
        }
        return try await downloadFile(url: url, destinationURL: destinationURL, expectedSha1: expectedSha1)
    }

    static func downloadFile(
        urlString: String,
        destinationURL: URL,
        expectedSha1: String? = nil,
        headers: [String: String]? = nil
    ) async throws -> URL {
        let url: URL = try autoreleasepool {
            guard let url = URL(string: urlString) else {
                throw GlobalError.validation(
                    chineseMessage: "无效的下载地址",
                    i18nKey: "error.validation.invalid_download_url",
                    level: .notification
                )
            }
            return url
        }
        return try await downloadFile(url: url, destinationURL: destinationURL, expectedSha1: expectedSha1, headers: headers)
    }

    /// 通用下载文件到指定路径（内部方法，接受 URL 对象）
    /// - Parameters:
    ///   - url: 下载地址（URL 对象）
    ///   - destinationURL: 目标文件路径
    ///   - expectedSha1: 预期 SHA1 值
    /// - Returns: 下载到的本地文件 URL
    /// - Throws: GlobalError 当操作失败时
    private static func downloadFile(
        url: URL,
        destinationURL: URL,
        expectedSha1: String? = nil
    ) async throws -> URL {
        return try await downloadViaCLI(
            url: url,
            destinationURL: destinationURL,
            expectedSha1: expectedSha1,
            headers: nil
        )
    }

    private static func downloadViaCLI(
        url: URL,
        destinationURL: URL,
        expectedSha1: String? = nil,
        headers: [String: String]? = nil
    ) async throws -> URL {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw GlobalError.fileSystem(
                chineseMessage: "创建目标目录失败",
                i18nKey: "error.filesystem.download_directory_creation_failed",
                level: .notification
            )
        }

        var arguments = [
            "game", "download-file",
            "--url", url.absoluteString,
            "--destination", destinationURL.path,
        ]
        if let expectedSha1, !expectedSha1.isEmpty {
            arguments.append(contentsOf: ["--sha1", expectedSha1])
        }
        if let headers, !headers.isEmpty {
            let data = try JSONSerialization.data(withJSONObject: headers, options: [.sortedKeys])
            guard let json = String(data: data, encoding: .utf8) else {
                throw ScslCoreCLIError.invalidUTF8
            }
            arguments.append(contentsOf: ["--headers-json", json])
        }

        let response: ScslCoreCLIEnvelope<GenericDownloadCLIResponse> = try await ScslCoreCLIService.shared.runJSON(
            arguments: arguments
        )
        let resolvedPath = response.data.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedPath.isEmpty else {
            throw GlobalError.download(
                chineseMessage: "core 未返回下载后的文件路径",
                i18nKey: "error.download.general_failure",
                level: .notification
            )
        }
        return URL(fileURLWithPath: resolvedPath)
    }

    private static func downloadFile(
        url: URL,
        destinationURL: URL,
        expectedSha1: String? = nil,
        headers: [String: String]? = nil
    ) async throws -> URL {
        return try await downloadViaCLI(
            url: url,
            destinationURL: destinationURL,
            expectedSha1: expectedSha1,
            headers: headers
        )
    }

    private static func downloadWithProgress(
        request: URLRequest,
        trackingId _: UUID?
    ) async throws -> (URL, URLResponse) {
        let (tempFileURL, response) = try await URLSession.shared.download(for: request)
        let persistedURL = try persistTemporaryFile(tempFileURL)
        return (persistedURL, response)
    }

    private static func downloadWithProgressOrFallback(
        request: URLRequest,
        trackingId: UUID?
    ) async throws -> (URL, URLResponse) {
        try await downloadWithProgress(request: request, trackingId: trackingId)
    }

    /// 计算文件的 SHA1 哈希值
    /// - Parameter url: 文件路径
    /// - Returns: SHA1 哈希字符串
    /// - Throws: GlobalError 当操作失败时
    static func calculateFileSHA1(at url: URL) throws -> String {
        return try SHA1Calculator.sha1(ofFileAt: url)
    }
}
