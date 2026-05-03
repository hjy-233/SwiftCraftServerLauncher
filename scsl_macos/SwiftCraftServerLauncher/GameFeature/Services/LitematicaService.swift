import Foundation

/// Litematica 投影文件服务
/// 负责读取和解析 Litematica 投影文件
@MainActor
class LitematicaService {
    static let shared = LitematicaService()

    private init() {}

    /// 从游戏目录读取 Litematica 投影文件列表
    /// - Parameter gameName: 游戏名称
    /// - Returns: Litematica 投影文件列表
    func loadLitematicaFiles(for gameName: String) async throws -> [LitematicaInfo] {
        let schematicsDir = AppPaths.schematicsDirectory(gameName: gameName)
        do {
            return try await Task.detached(priority: .userInitiated) {
                try loadLitematicaFilesSync(schematicsDir: schematicsDir)
            }.value
        } catch {
            Logger.shared.error("读取 Litematica 文件列表失败: \(error.localizedDescription)")
            throw GlobalError.fileSystem(
                chineseMessage: "读取 Litematica 文件列表失败",
                i18nKey: "error.filesystem.litematica_list_read_failed",
                level: .notification
            )
        }
    }

    /// 解析 Litematica 文件的元数据（用于列表显示）
    /// - Parameter filePath: 文件路径
    /// - Returns: 元数据信息
    private func parseLitematicaMetadata(filePath: URL) async throws -> LitematicaMetadata? {
        let response: ScslCoreCLIEnvelope<LitematicaMetadataCLIResponse> = try await ScslCoreCLIService.shared.runJSON(
            arguments: ["game", "litematica-metadata", "--path", filePath.path]
        )
        return response.data.asMetadata
    }

    /// 读取完整的 Litematica 投影元数据
    /// - Parameter filePath: 文件路径
    /// - Returns: 完整的元数据信息
    func loadFullMetadata(filePath: URL) async throws -> LitematicMetadata? {
        do {
            let response: ScslCoreCLIEnvelope<LitematicaFullMetadataCLIResponse> = try await ScslCoreCLIService.shared.runJSON(
                arguments: ["game", "litematica-full-metadata", "--path", filePath.path]
            )
            return response.data.asMetadata(filePath: filePath)
        } catch {
            Logger.shared.error("解析Litematica文件失败: \(filePath.lastPathComponent), 错误: \(error)")
            throw error
        }
    }
}

// MARK: - 文件内同步辅助（在 Task.detached 中调用，避免主线程文件 I/O）
private func loadLitematicaFilesSync(schematicsDir: URL) throws -> [LitematicaInfo] {
    guard FileManager.default.fileExists(atPath: schematicsDir.path) else { return [] }
    let contents = try FileManager.default.contentsOfDirectory(
        at: schematicsDir,
        includingPropertiesForKeys: [.isRegularFileKey, .creationDateKey, .fileSizeKey],
        options: [.skipsHiddenFiles]
    )
    var litematicaFiles: [LitematicaInfo] = []
    for filePath in contents {
        guard let isFile = try? filePath.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile, isFile == true else { continue }
        guard filePath.pathExtension.lowercased() == "litematic" else { continue }
        let fileName = filePath.lastPathComponent
        let creationDate = try? filePath.resourceValues(forKeys: [.creationDateKey]).creationDate
        let fileSize = (try? filePath.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let json = try callLitematicaMetadataCLI(path: filePath.path)
        let metadata = json.asMetadata
        litematicaFiles.append(LitematicaInfo(
            name: fileName,
            path: filePath,
            createdDate: creationDate,
            fileSize: Int64(fileSize),
            author: metadata.author,
            description: metadata.description,
            version: metadata.version,
            regionCount: metadata.regionCount,
            totalBlocks: metadata.totalBlocks
        ))
    }
    litematicaFiles.sort { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
    return litematicaFiles
}

private func callLitematicaMetadataCLI(path: String) throws -> LitematicaMetadataCLIResponse {
    let task = DispatchSemaphore(value: 0)
    var result: Result<LitematicaMetadataCLIResponse, Error>?
    Task {
        defer { task.signal() }
        do {
            let response: ScslCoreCLIEnvelope<LitematicaMetadataCLIResponse> = try await ScslCoreCLIService.shared.runJSON(
                arguments: ["game", "litematica-metadata", "--path", path]
            )
            result = .success(response.data)
        } catch {
            result = .failure(error)
        }
    }
    task.wait()
    guard let result else {
        throw ScslCoreCLIError.executionFailed("Litematica 元数据解析未返回结果")
    }
    return try result.get()
}

private struct LitematicaMetadataCLIResponse: Decodable {
    let author: String?
    let description: String?
    let version: String?
    let regionCount: Int?
    let totalBlocks: Int?

    var asMetadata: LitematicaMetadata {
        LitematicaMetadata(
            author: author,
            description: description,
            version: version,
            regionCount: regionCount,
            totalBlocks: totalBlocks
        )
    }
}

private struct LitematicaFullMetadataCLIResponse: Decodable {
    let name: String
    let author: String
    let description: String
    let timeCreated: Int64
    let timeModified: Int64
    let totalVolume: Int32
    let totalBlocks: Int32
    let enclosingSize: LitematicaSizeCLIResponse
    let regionCount: Int32

    func asMetadata(filePath: URL) -> LitematicMetadata {
        LitematicMetadata(
            name: name.isEmpty ? filePath.deletingPathExtension().lastPathComponent : name,
            author: author,
            description: description,
            timeCreated: timeCreated,
            timeModified: timeModified,
            totalVolume: totalVolume,
            totalBlocks: totalBlocks,
            enclosingSize: enclosingSize.asSize,
            regionCount: regionCount
        )
    }
}

private struct LitematicaSizeCLIResponse: Decodable {
    let x: Int32
    let y: Int32
    let z: Int32

    var asSize: Size {
        Size(x: x, y: y, z: z)
    }
}
