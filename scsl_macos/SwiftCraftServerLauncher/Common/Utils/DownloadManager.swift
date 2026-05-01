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

        let output = try await ScslCoreCLIService.shared.run(arguments: arguments)
        let resolvedPath = output.trimmingCharacters(in: .whitespacesAndNewlines)
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
        // 优化：在同步部分使用 autoreleasepool 及时释放临时对象
        // 优化：直接使用 URL，避免同时存储 String 和 URL（节省内存）
        let finalURL: URL = autoreleasepool {
            // 优化：直接使用 URL 的 host 属性检查，避免转换为 String
            let needsProxy: Bool
            if let host = url.host {
                needsProxy = host == githubHost || host == rawGithubHost
            } else {
                // 如果没有 host，检查 absoluteString（可能是相对路径）
                let absoluteString = url.absoluteString
                needsProxy = absoluteString.hasPrefix(githubPrefix) || absoluteString.hasPrefix(rawGithubPrefix)
            }

            if needsProxy {
                return URLConfig.applyGitProxyIfNeeded(url)
            } else {
                return url
            }
        }

        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw GlobalError.fileSystem(
                chineseMessage: "创建目标目录失败",
                i18nKey: "error.filesystem.download_directory_creation_failed",
                level: .notification
            )
        }

        // 检查是否需要 SHA1 校验
        let shouldCheckSha1 = (expectedSha1?.isEmpty == false)

        // 如果文件已存在
        let destinationPath = destinationURL.path
        if fileManager.fileExists(atPath: destinationPath) {
            if shouldCheckSha1, let expectedSha1 = expectedSha1 {
                // 优化：使用 autoreleasepool 释放 SHA1 计算过程中的临时对象
                do {
                    let actualSha1 = try autoreleasepool {
                        try calculateFileSHA1(at: destinationURL)
                    }
                    if actualSha1 == expectedSha1 {
                        return destinationURL
                    }
                    // 如果校验失败，继续下载（不返回，继续执行下面的下载逻辑）
                } catch {
                    // 如果校验出错，继续下载（不中断）
                }
            } else {
                // 没有 SHA1 时直接跳过
                return destinationURL
            }
        }

        // 下载文件到临时位置（异步操作在 autoreleasepool 外部）
        let trackingInfo = trackingInfo(for: destinationURL)
        let trackingId: UUID? = await MainActor.run {
            guard let trackingInfo else { return nil }
            return DownloadCenter.shared.startTask(
                title: trackingInfo.title,
                iconSystemName: trackingInfo.iconSystemName
            )
        }

        do {
            let request = URLRequest(url: finalURL)
            let (tempFileURL, response) = try await downloadWithProgressOrFallback(
                request: request,
                trackingId: trackingId
            )
            defer {
                // 确保临时文件被清理
                try? fileManager.removeItem(at: tempFileURL)
            }

            // 优化：直接检查状态码，减少中间变量
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw GlobalError.download(
                    chineseMessage: "HTTP 请求失败",
                    i18nKey: "error.download.http_status_error",
                    level: .notification
                )
            }

            // SHA1 校验（优化：使用 autoreleasepool）
            if shouldCheckSha1, let expectedSha1 = expectedSha1 {
                try autoreleasepool {
                    let actualSha1 = try calculateFileSHA1(at: tempFileURL)
                    if actualSha1 != expectedSha1 {
                        throw GlobalError.validation(
                            chineseMessage: "SHA1 校验失败",
                            i18nKey: "error.validation.sha1_check_failed",
                            level: .notification
                        )
                    }
                }
            }

            // 原子性地移动到最终位置
            if fileManager.fileExists(atPath: destinationURL.path) {
                // 先尝试直接替换
                try fileManager.replaceItem(at: destinationURL, withItemAt: tempFileURL, backupItemName: nil, options: [], resultingItemURL: nil)
            } else {
                try fileManager.moveItem(at: tempFileURL, to: destinationURL)
            }

            await MainActor.run {
                if let trackingId {
                    DownloadCenter.shared.finishTask(id: trackingId, success: true)
                }
            }
            return destinationURL
        } catch {
            await MainActor.run {
                if let trackingId {
                    DownloadCenter.shared.finishTask(id: trackingId, success: false)
                }
            }
            // 转换错误为 GlobalError
            if let globalError = error as? GlobalError {
                throw globalError
            } else if let urlError = error as? URLError, urlError.code == .cancelled {
                throw GlobalError.download(
                    chineseMessage: "下载已取消",
                    i18nKey: "error.download.cancelled",
                    level: .notification
                )
            } else if error is URLError {
                throw GlobalError.download(
                    chineseMessage: "网络请求失败",
                    i18nKey: "error.download.network_request_failed",
                    level: .notification
                )
            } else {
                throw GlobalError.download(
                    chineseMessage: "下载失败",
                    i18nKey: "error.download.general_failure",
                    level: .notification
                )
            }
        }
    }

    private static func downloadFile(
        url: URL,
        destinationURL: URL,
        expectedSha1: String? = nil,
        headers: [String: String]? = nil
    ) async throws -> URL {
        let finalURL: URL = autoreleasepool {
            let needsProxy: Bool
            if let host = url.host {
                needsProxy = host == githubHost || host == rawGithubHost
            } else {
                let absoluteString = url.absoluteString
                needsProxy = absoluteString.hasPrefix(githubPrefix) || absoluteString.hasPrefix(rawGithubPrefix)
            }

            if needsProxy {
                return URLConfig.applyGitProxyIfNeeded(url)
            } else {
                return url
            }
        }

        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw GlobalError.fileSystem(
                chineseMessage: "创建目标目录失败",
                i18nKey: "error.filesystem.download_directory_creation_failed",
                level: .notification
            )
        }

        let shouldCheckSha1 = (expectedSha1?.isEmpty == false)

        let destinationPath = destinationURL.path
        if fileManager.fileExists(atPath: destinationPath) {
            if shouldCheckSha1, let expectedSha1 = expectedSha1 {
                do {
                    let actualSha1 = try autoreleasepool {
                        try calculateFileSHA1(at: destinationURL)
                    }
                    if actualSha1 == expectedSha1 {
                        return destinationURL
                    }
                } catch {
                }
            } else {
                return destinationURL
            }
        }

        let trackingInfo = trackingInfo(for: destinationURL)
        let trackingId: UUID? = await MainActor.run {
            guard let trackingInfo else { return nil }
            return DownloadCenter.shared.startTask(
                title: trackingInfo.title,
                iconSystemName: trackingInfo.iconSystemName
            )
        }

        do {
            var request = URLRequest(url: finalURL)
            if let headers = headers {
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }
            let (tempFileURL, response) = try await downloadWithProgressOrFallback(
                request: request,
                trackingId: trackingId
            )
            defer {
                try? fileManager.removeItem(at: tempFileURL)
            }

            if !fileManager.fileExists(atPath: tempFileURL.path) {
                throw GlobalError.download(
                    chineseMessage: "下载临时文件不存在",
                    i18nKey: "error.download.temp_file_missing",
                    level: .notification
                )
            }

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw GlobalError.download(
                    chineseMessage: "HTTP 请求失败",
                    i18nKey: "error.download.http_status_error",
                    level: .notification
                )
            }

            if shouldCheckSha1, let expectedSha1 = expectedSha1 {
                try autoreleasepool {
                    let actualSha1 = try calculateFileSHA1(at: tempFileURL)
                    if actualSha1 != expectedSha1 {
                        throw GlobalError.validation(
                            chineseMessage: "SHA1 校验失败",
                            i18nKey: "error.validation.sha1_check_failed",
                            level: .notification
                        )
                    }
                }
            }

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.replaceItem(at: destinationURL, withItemAt: tempFileURL, backupItemName: nil, options: [], resultingItemURL: nil)
            } else {
                try fileManager.moveItem(at: tempFileURL, to: destinationURL)
            }

            await MainActor.run {
                if let trackingId {
                    DownloadCenter.shared.finishTask(id: trackingId, success: true)
                }
            }
            return destinationURL
        } catch {
            await MainActor.run {
                if let trackingId {
                    DownloadCenter.shared.finishTask(id: trackingId, success: false)
                }
            }
            if let globalError = error as? GlobalError {
                throw globalError
            } else if let urlError = error as? URLError, urlError.code == .cancelled {
                throw GlobalError.download(
                    chineseMessage: "下载已取消",
                    i18nKey: "error.download.cancelled",
                    level: .notification
                )
            } else if error is URLError {
                throw GlobalError.download(
                    chineseMessage: "网络请求失败",
                    i18nKey: "error.download.network_request_failed",
                    level: .notification
                )
            } else if let fileError = error as? CocoaError {
                throw GlobalError.fileSystem(
                    chineseMessage: "文件操作失败: \(fileError.localizedDescription)",
                    i18nKey: "error.filesystem.operation_failed",
                    level: .notification
                )
            } else {
                throw GlobalError.download(
                    chineseMessage: "下载失败: \(error.localizedDescription)",
                    i18nKey: "error.download.general_failure",
                    level: .notification
                )
            }
        }
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
