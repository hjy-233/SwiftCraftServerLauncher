import Foundation

// MARK: - JSONDecoder Extension for Modrinth Date Handling
private extension JSONDecoder {
    /// Configures the decoder with Modrinth's custom date decoding strategy
    func configureForModrinth() {
        self.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateStr = try container.decode(String.self)

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            formatter.timeZone = TimeZone(secondsFromGMT: 0)

            if let date = formatter.date(from: dateStr) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date: \(dateStr)"
            )
        }
    }
}

enum ModrinthService {
    static func fetchVersionInfo(from version: String) async throws -> MinecraftVersionManifest {
        let cacheKey = "version_info_\(version)"

        // 检查缓存
        if let cachedVersionInfo: MinecraftVersionManifest = AppCacheManager.shared.get(namespace: "version_info", key: cacheKey, as: MinecraftVersionManifest.self) {
            return cachedVersionInfo
        }

        // 从API获取版本信息
        let versionInfo = try await fetchVersionInfoThrowing(from: version)

        // 缓存整个版本信息
        AppCacheManager.shared.setSilently(
            namespace: "version_info",
            key: cacheKey,
            value: versionInfo
        )

        return versionInfo
    }

    static func queryVersionTime(from version: String) async -> String {
        let cacheKey = "version_time_\(version)"

        // 检查缓存
        if let cachedTime: String = AppCacheManager.shared.get(namespace: "version_time", key: cacheKey, as: String.self) {
            return cachedTime
        }

        do {
            // 使用缓存的版本信息，避免重复API调用
            let versionInfo = try await Self.fetchVersionInfo(from: version)
            let formattedTime = CommonUtil.formatRelativeTime(versionInfo.releaseTime)

            // 缓存版本时间信息
            AppCacheManager.shared.setSilently(
                namespace: "version_time",
                key: cacheKey,
                value: formattedTime
            )
            return formattedTime
        } catch {
            return ""
        }
    }

    static func fetchVersionInfoThrowing(from version: String) async throws -> MinecraftVersionManifest {
        let response: ScslCoreCLIEnvelope<MinecraftVersionManifest> = try await ScslCoreCLIService.shared.runJSON(
            arguments: ["modrinth", "version-info", version]
        )
        return response.data
    }

    static func searchProjects(
        facets: [[String]]? = nil,
        offset: Int = 0,
        limit: Int,
        query: String?
    ) async -> ModrinthResult {
        return await Task {
            try await searchProjectsThrowing(
                facets: facets,
                index: AppConstants.modrinthIndex,
                offset: offset,
                limit: limit,
                query: query
            )
        }.catching { error in
            let globalError = GlobalError.from(error)
            Logger.shared.error("搜索 Modrinth 项目失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return ModrinthResult(hits: [], offset: offset, limit: limit, totalHits: 0)
        }
    }

    static func searchProjectsThrowing(
        facets: [[String]]? = nil,
        index: String,
        offset: Int = 0,
        limit: Int,
        query: String?
    ) async throws -> ModrinthResult {
        var arguments = [
            "modrinth", "search",
            "--index", index,
            "--offset", String(offset),
            "--limit", String(min(limit, 100)),
        ]
        if let query, !query.isEmpty {
            arguments.append(contentsOf: ["--query", query])
        }
        if let facets = facets {
            do {
                let facetsJson = try JSONEncoder().encode(facets)
                if let facetsString = String(data: facetsJson, encoding: .utf8) {
                    arguments.append(contentsOf: ["--facets-json", facetsString])
                }
            } catch {
                throw GlobalError.validation(
                    chineseMessage: "编码搜索条件失败: \(error.localizedDescription)",
                    i18nKey: "error.validation.search_condition_encode_failed",
                    level: .notification
                )
            }
        }
        let response: ScslCoreCLIEnvelope<ModrinthResult> = try await ScslCoreCLIService.shared.runJSON(arguments: arguments)
        return response.data
    }

    static func fetchLoaders() async -> [Loader] {
        do {
            return try await fetchLoadersThrowing()
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("获取 Modrinth 加载器列表失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return []
        }
    }

    static func fetchLoadersThrowing() async throws -> [Loader] {
        let response: ScslCoreCLIEnvelope<[Loader]> = try await ScslCoreCLIService.shared.runJSON(arguments: ["modrinth", "loaders"])
        return response.data
    }

    static func fetchCategories() async -> [Category] {
        do {
            return try await fetchCategoriesThrowing()
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("获取 Modrinth 分类列表失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return []
        }
    }

    static func fetchCategoriesThrowing() async throws -> [Category] {
        let response: ScslCoreCLIEnvelope<[Category]> = try await ScslCoreCLIService.shared.runJSON(arguments: ["modrinth", "categories"])
        return response.data
    }

    static func fetchGameVersions(includeSnapshots: Bool = false) async -> [GameVersion] {
        do {
            return try await fetchGameVersionsThrowing(includeSnapshots: includeSnapshots)
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("获取 Modrinth 游戏版本列表失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return []
        }
    }

    static func fetchGameVersionsThrowing(
        includeSnapshots: Bool = false
    ) async throws -> [GameVersion] {
        var arguments = ["modrinth", "game-versions"]
        if includeSnapshots {
            arguments.append("--include-snapshots")
        }
        let response: ScslCoreCLIEnvelope<[GameVersion]> = try await ScslCoreCLIService.shared.runJSON(arguments: arguments)
        return response.data
    }

    static func fetchProjectDetails(id: String) async -> ModrinthProjectDetail? {
        do {
            return try await fetchProjectDetailsThrowing(id: id)
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("获取项目详情失败 (ID: \(id)): \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return nil
        }
    }

    static func fetchProjectDetailsThrowing(id: String) async throws -> ModrinthProjectDetail {
        if id.hasPrefix("cf-") {
            throw GlobalError.validation(
                chineseMessage: "CurseForge 已停用",
                i18nKey: "error.validation.server_not_selected",
                level: .notification
            )
        }
        let response: ScslCoreCLIEnvelope<ModrinthProjectDetail> = try await ScslCoreCLIService.shared.runJSON(
            arguments: ["modrinth", "project", id]
        )
        var detail = response.data

        // 仅保留纯数字（含点号）的正式版游戏版本，例如 1.20.4
        let releaseGameVersions = detail.gameVersions.filter {
            $0.range(of: #"^\d+(\.\d+)*$"#, options: .regularExpression) != nil
        }
        detail.gameVersions = CommonUtil.sortMinecraftVersions(releaseGameVersions)

        return detail
    }

    static func fetchProjectVersions(id: String) async -> [ModrinthProjectDetailVersion] {
        do {
            return try await fetchProjectVersionsThrowing(id: id)
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("获取项目版本列表失败 (ID: \(id)): \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return []
        }
    }

    static func fetchProjectVersionsThrowing(id: String) async throws -> [ModrinthProjectDetailVersion] {
        if id.hasPrefix("cf-") {
            throw GlobalError.validation(
                chineseMessage: "CurseForge 已停用",
                i18nKey: "error.validation.server_not_selected",
                level: .notification
            )
        }
        let response: ScslCoreCLIEnvelope<[ModrinthProjectDetailVersion]> = try await ScslCoreCLIService.shared.runJSON(
            arguments: ["modrinth", "versions", id]
        )
        return response.data
    }

    static func fetchProjectVersionsFilter(
            id: String,
            selectedVersions: [String],
            selectedLoaders: [String],
            type: String
        ) async throws -> [ModrinthProjectDetailVersion] {
            // 检查是否是 CurseForge 项目（ID 以 "cf-" 开头）
        if id.hasPrefix("cf-") {
                throw GlobalError.validation(
                    chineseMessage: "CurseForge 已停用",
                    i18nKey: "error.validation.server_not_selected",
                    level: .notification
                )
            }

            let selectedVersionsData = try JSONEncoder().encode(selectedVersions)
            let selectedLoadersData = try JSONEncoder().encode(selectedLoaders)
            guard let selectedVersionsJSON = String(data: selectedVersionsData, encoding: .utf8),
                  let selectedLoadersJSON = String(data: selectedLoadersData, encoding: .utf8) else {
                throw GlobalError.validation(
                    chineseMessage: "版本筛选参数编码失败",
                    i18nKey: "error.validation.search_condition_encode_failed",
                    level: .notification
                )
            }
            let response: ScslCoreCLIEnvelope<[ModrinthProjectDetailVersion]> = try await ScslCoreCLIService.shared.runJSON(
                arguments: [
                    "modrinth", "versions-filter",
                    "--id", id,
                    "--type", type,
                    "--selected-versions-json", selectedVersionsJSON,
                    "--selected-loaders-json", selectedLoadersJSON,
                ]
            )
            return response.data
        }

    static func fetchProjectDependencies(
        type: String,
        cachePath: URL,
        id: String,
        selectedVersions: [String],
        selectedLoaders: [String]
    ) async -> ModrinthProjectDependency {
        do {
            return try await fetchProjectDependenciesThrowing(
                type: type,
                cachePath: cachePath,
                id: id,
                selectedVersions: selectedVersions,
                selectedLoaders: selectedLoaders
            )
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("获取项目依赖失败 (ID: \(id)): \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return ModrinthProjectDependency(projects: [])
        }
    }

    static func fetchProjectDependenciesThrowing(
        type: String,
        cachePath: URL,
        id: String,
        selectedVersions: [String],
        selectedLoaders: [String]
    ) async throws -> ModrinthProjectDependency {
        if id.hasPrefix("cf-") {
            throw GlobalError.validation(
                chineseMessage: "CurseForge 已停用",
                i18nKey: "error.validation.server_not_selected",
                level: .notification
            )
        }

        let selectedVersionsData = try JSONEncoder().encode(selectedVersions)
        let selectedLoadersData = try JSONEncoder().encode(selectedLoaders)
        guard let selectedVersionsJSON = String(data: selectedVersionsData, encoding: .utf8),
              let selectedLoadersJSON = String(data: selectedLoadersData, encoding: .utf8) else {
            throw GlobalError.validation(
                chineseMessage: "依赖参数编码失败",
                i18nKey: "error.validation.search_condition_encode_failed",
                level: .notification
            )
        }
        let response: ScslCoreCLIEnvelope<ModrinthProjectDependency> = try await ScslCoreCLIService.shared.runJSON(
            arguments: [
                "modrinth", "dependencies",
                "--id", id,
                "--type", type,
                "--selected-versions-json", selectedVersionsJSON,
                "--selected-loaders-json", selectedLoadersJSON,
            ]
        )

        // 3. 使用hash检查是否已安装，过滤出缺失的依赖
        let missingDependencyVersions = response.data.projects.filter { version in
            // 获取主文件的hash
            guard let primaryFile = Self.filterPrimaryFiles(from: version.files) else {
                return true // 如果没有主文件，认为缺失
            }
            // 使用hash检查是否已安装
            return !ModScanner.shared.isModInstalledSync(hash: primaryFile.hashes.sha1, in: cachePath)
        }

        return ModrinthProjectDependency(projects: missingDependencyVersions)
    }

    static func fetchProjectVersionThrowing(id: String) async throws -> ModrinthProjectDetailVersion {
        let response: ScslCoreCLIEnvelope<ModrinthProjectDetailVersion> = try await ScslCoreCLIService.shared.runJSON(
            arguments: ["modrinth", "version", id]
        )
        return response.data
    }

    // 过滤主文件
    static func filterPrimaryFiles(from files: [ModrinthVersionFile]?) -> ModrinthVersionFile? {
        return files?.first { $0.primary == true }
    }

    static func fetchModrinthDetail(by hash: String, completion: @escaping (ModrinthProjectDetail?) -> Void) {
        Task {
            do {
                let response: ScslCoreCLIEnvelope<ModrinthProjectDetailVersion> = try await ScslCoreCLIService.shared.runJSON(
                    arguments: ["modrinth", "file-by-hash", hash]
                )
                let version = response.data
                let detail = try await Self.fetchProjectDetailsThrowing(id: version.projectId)
                await MainActor.run { completion(detail) }
            } catch {
                let globalError = GlobalError.from(error)
                Logger.shared.error("通过哈希获取项目详情失败 (Hash: \(hash)): \(globalError.chineseMessage)")
                GlobalErrorHandler.shared.handle(globalError)
                await MainActor.run { completion(nil) }
            }
        }
    }
}

// Extension to support catching errors in async function returning a value.
private extension Task where Success == ModrinthResult, Failure == Error {
    func catching(_ handler: @escaping (Error) -> ModrinthResult) async -> ModrinthResult {
        do {
            return try await value
        } catch {
            return handler(error)
        }
    }
}
