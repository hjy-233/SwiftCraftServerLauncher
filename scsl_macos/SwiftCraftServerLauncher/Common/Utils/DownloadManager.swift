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

    private struct TrackingInfo {
        let title: String
        let iconSystemName: String
    }

    private struct ResourceDownloadCLIResponse: Decodable {
        let path: String
    }

    private struct GenericDownloadCLIResponse: Decodable {
        let path: String
    }

    private static var activeSessions: [UUID: URLSession] = [:]
    private static var activeDelegates: [UUID: DownloadProgressDelegate] = [:]
    private static let activeSessionsLock = NSLock()

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

    private static func trackingInfo(for destinationURL: URL) -> TrackingInfo? {
        let path = destinationURL.path.lowercased()
        let fileName = destinationURL.lastPathComponent

        if path.contains("/\(AppConstants.DirectoryNames.plugins)/") {
            return TrackingInfo(title: fileName, iconSystemName: "powerplug")
        }
        if path.contains("/\(AppConstants.DirectoryNames.mods)/") {
            return TrackingInfo(title: fileName, iconSystemName: "puzzlepiece.extension")
        }
        if path.contains("/\(AppConstants.DirectoryNames.datapacks)/") {
            return TrackingInfo(title: fileName, iconSystemName: "doc.on.doc")
        }
        if path.contains("/\(AppConstants.DirectoryNames.shaderpacks)/") {
            return TrackingInfo(title: fileName, iconSystemName: "sparkles")
        }
        if path.contains("/\(AppConstants.DirectoryNames.resourcepacks)/") {
            return TrackingInfo(title: fileName, iconSystemName: "photo.stack")
        }
        if path.contains("/\(AppConstants.DirectoryNames.servers)/"),
           destinationURL.pathExtension.lowercased() == AppConstants.FileExtensions.jar {
            return TrackingInfo(title: "服务器核心: \(fileName)", iconSystemName: "server.rack")
        }
        return nil
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

    fileprivate final class DownloadProgressDelegate: NSObject {
        private let progressHandler: (Int64, Int64) -> Void
        private let completion: (Result<(URL, URLResponse), Error>) -> Void
        private var tempFileURL: URL?
        private var tempFileError: Error?
        private var didComplete = false

        init(
            progressHandler: @escaping (Int64, Int64) -> Void,
            completion: @escaping (Result<(URL, URLResponse), Error>) -> Void
        ) {
            self.progressHandler = progressHandler
            self.completion = completion
        }
    }

    private static func downloadWithProgress(
        request: URLRequest,
        trackingId: UUID?
    ) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            var session: URLSession?
            var task: URLSessionDownloadTask?
            let sessionId = UUID()
            let delegate = DownloadProgressDelegate(
                progressHandler: { received, expected in
                    guard let trackingId else { return }
                    let progress: Double?
                    if expected > 0 {
                        progress = max(0, min(1, Double(received) / Double(expected)))
                    } else {
                        progress = nil
                    }
                    Task { @MainActor in
                        DownloadCenter.shared.updateProgress(id: trackingId, progress: progress)
                    }
                },
                completion: { result in
                    activeSessionsLock.lock()
                    activeSessions[sessionId] = nil
                    activeDelegates[sessionId] = nil
                    activeSessionsLock.unlock()
                    continuation.resume(with: result)
                }
            )
            session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            activeSessionsLock.lock()
            activeSessions[sessionId] = session
            activeDelegates[sessionId] = delegate
            activeSessionsLock.unlock()
            task = session?.downloadTask(with: request)
            guard let task else {
                activeSessionsLock.lock()
                activeSessions[sessionId] = nil
                activeDelegates[sessionId] = nil
                activeSessionsLock.unlock()
                continuation.resume(throwing: URLError(.unknown))
                return
            }
            if let trackingId {
                Task { @MainActor in
                    DownloadCenter.shared.registerCancel(id: trackingId) {
                        task.cancel()
                    }
                }
            }
            task.resume()
        }
    }

    private static func downloadWithProgressOrFallback(
        request: URLRequest,
        trackingId: UUID?
    ) async throws -> (URL, URLResponse) {
        do {
            return try await downloadWithProgress(request: request, trackingId: trackingId)
        } catch {
            if let urlError = error as? URLError, urlError.code == .cancelled {
                throw error
            }
            let wasCancelled = await MainActor.run {
                guard let trackingId else { return false }
                return DownloadCenter.shared.wasCancelled(id: trackingId)
            }
            if wasCancelled {
                throw URLError(.cancelled)
            }
            let (tempFileURL, response) = try await URLSession.shared.download(for: request)
            let persistedURL = try persistTemporaryFile(tempFileURL)
            return (persistedURL, response)
        }
    }

    /// 计算文件的 SHA1 哈希值
    /// - Parameter url: 文件路径
    /// - Returns: SHA1 哈希字符串
    /// - Throws: GlobalError 当操作失败时
    static func calculateFileSHA1(at url: URL) throws -> String {
        return try SHA1Calculator.sha1(ofFileAt: url)
    }
}

extension DownloadManager.DownloadProgressDelegate: URLSessionDownloadDelegate, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            tempFileURL = try DownloadManager.persistTemporaryFile(location)
        } catch {
            tempFileError = error
            tempFileURL = location
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        progressHandler(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard !didComplete else { return }
        didComplete = true
        if let error {
            completion(.failure(error))
            return
        }
        if let tempFileError {
            completion(.failure(tempFileError))
            return
        }
        guard let tempFileURL, let response = task.response else {
            completion(.failure(URLError(.unknown)))
            return
        }
        completion(.success((tempFileURL, response)))
    }
}
