import Foundation

extension ServerCreationViewModel {
    func handleServerTypeChange(_ newType: ServerType) {
        selectedServerType = newType
        selectedLoaderVersion = ""
        Task {
            await refreshAvailableVersions(for: newType)

            if requiresLoaderVersion(newType), !selectedGameVersion.isEmpty {
                await updateLoaderVersions(for: newType, gameVersion: selectedGameVersion)
            } else {
                await MainActor.run {
                    availableLoaderVersions = []
                    selectedLoaderVersion = ""
                }
            }
        }
    }

    func handleMirrorSourceChange(_ newSource: ServerMirrorSource) {
        if newSource == .fastMirror {
            resetMirrorSelections()
            if selectedServerType == .custom {
                selectedServerType = .vanilla
            }
            Task {
                await loadFastMirrorCores()
                await refreshAvailableVersions(for: selectedServerType)
            }
            return
        }
        if newSource == .custom {
            resetMirrorSelections()
            Task {
                await loadCustomMirrorCores()
                await refreshAvailableVersions(for: selectedServerType)
            }
            return
        }
        if newSource == .polars {
            resetMirrorSelections()
            Task { await loadPolarsCoreTypes() }
            return
        }
        resetMirrorSelections()
        selectedLoaderVersion = ""
        availableLoaderVersions = []
        Task {
            await refreshAvailableVersions(for: selectedServerType)
            if requiresLoaderVersion(selectedServerType), !selectedGameVersion.isEmpty {
                await updateLoaderVersions(for: selectedServerType, gameVersion: selectedGameVersion)
            }
        }
    }

    func applyMirrorSelection(
        sourceId: String,
        source: ServerMirrorSource,
        displayName: String,
        baseURL: String?,
        customJSON: String?
    ) {
        selectedMirrorSourceId = sourceId
        selectedMirrorDisplayName = displayName
        if source == .custom {
            let config = decodeCustomConfig(from: customJSON)
            selectedCustomConfig = config
            if let config, !config.baseURL.isEmpty {
                selectedMirrorBaseURL = config.baseURL
            } else {
                selectedMirrorBaseURL = baseURL ?? ""
            }
        } else {
            selectedCustomConfig = nil
            selectedMirrorBaseURL = baseURL ?? ""
        }
        selectedMirrorSource = source
    }

    func refreshAvailableVersions(for type: ServerType) async {
        let includeSnapshots = GameSettingsManager.shared.includeSnapshotsForGameVersions
        do {
            let versions: [String]
            if selectedMirrorSource == .fastMirror {
                guard !selectedFastMirrorCoreName.isEmpty else {
                    await updateAvailableVersions([])
                    return
                }
                versions = try await FastMirrorService.fetchGameVersions(
                    coreName: selectedFastMirrorCoreName,
                    baseURL: mirrorBaseURL()
                )
            } else if selectedMirrorSource == .custom {
                guard !selectedFastMirrorCoreName.isEmpty,
                      let config = selectedCustomConfig,
                      let baseURL = mirrorBaseURL() else {
                    await updateAvailableVersions([])
                    return
                }
                versions = try await CustomMirrorService.fetchGameVersions(
                    config: config,
                    baseURL: baseURL,
                    coreName: selectedFastMirrorCoreName
                )
            } else if selectedMirrorSource == .polars {
                await updateAvailableVersions([])
                return
            } else {
                versions = try await ServerDownloadService.fetchAvailableGameVersions(
                    serverType: type,
                    includeSnapshots: includeSnapshots
                )
            }
            await updateAvailableVersions(versions)
        } catch {
            Logger.shared.error("获取服务端版本失败: \(error.localizedDescription)")
            await updateAvailableVersions([])
            GlobalErrorHandler.shared.handle(error)
        }
    }

    func handleGameVersionChange(_ newVersion: String) {
        Task {
            if selectedMirrorSource == .custom {
                selectedMirrorDownloadURL = ""
                selectedMirrorFileName = ""
            }
            if requiresLoaderVersion(selectedServerType) {
                await updateLoaderVersions(for: selectedServerType, gameVersion: newVersion)
            }
        }
        updateParentState()
    }

    func handleMirrorCoreVersionChange(_ newVersion: String) {
        selectedLoaderVersion = newVersion
        guard selectedMirrorSource == .custom else { return }
        Task { await updateCustomMirrorDetail() }
        updateParentState()
    }

    private func requiresLoaderVersion(_ type: ServerType) -> Bool {
        if selectedMirrorSource == .fastMirror {
            return type != .custom
        }
        if selectedMirrorSource == .custom {
            return true
        }
        if selectedMirrorSource == .polars {
            return false
        }
        switch type {
        case .fabric, .forge:
            return true
        default:
            return false
        }
    }

    private func updateLoaderVersions(for type: ServerType, gameVersion: String) async {
        guard requiresLoaderVersion(type), !gameVersion.isEmpty else {
            availableLoaderVersions = []
            selectedLoaderVersion = ""
            updateParentState()
            return
        }

        var versions: [String] = []

        if selectedMirrorSource == .fastMirror {
            do {
                guard !selectedFastMirrorCoreName.isEmpty else {
                    versions = []
                    throw GlobalError.resource(
                        chineseMessage: "未选择核心",
                        i18nKey: "error.resource.not_found",
                        level: .notification
                    )
                }
                versions = try await FastMirrorService.fetchCoreVersions(
                    coreName: selectedFastMirrorCoreName,
                    gameVersion: gameVersion,
                    baseURL: mirrorBaseURL()
                )
            } catch {
                Logger.shared.error("获取镜像核心版本失败: \(error.localizedDescription)")
                versions = []
            }
        } else if selectedMirrorSource == .custom {
            do {
                guard !selectedFastMirrorCoreName.isEmpty,
                      let config = selectedCustomConfig,
                      let baseURL = mirrorBaseURL() else {
                    versions = []
                    throw GlobalError.resource(
                        chineseMessage: "未选择核心",
                        i18nKey: "error.resource.not_found",
                        level: .notification
                    )
                }
                versions = try await CustomMirrorService.fetchCoreVersions(
                    config: config,
                    baseURL: baseURL,
                    coreName: selectedFastMirrorCoreName,
                    gameVersion: gameVersion
                )
            } catch {
                Logger.shared.error("获取镜像核心版本失败: \(error.localizedDescription)")
                versions = []
            }
        } else {
        switch type {
        case .fabric:
            let fabricVersions = await FabricLoaderService.fetchAllLoaderVersions(for: gameVersion)
            versions = fabricVersions.map { $0.loader.version }
        case .forge:
            do {
                let forgeVersions = try await ForgeLoaderService.fetchAllForgeVersions(for: gameVersion)
                versions = forgeVersions.loaders.map { $0.id }
            } catch {
                Logger.shared.error("获取 Forge 版本失败: \(error.localizedDescription)")
                versions = []
            }
        default:
            versions = []
        }
        }

        availableLoaderVersions = versions
        if versions.isEmpty {
            selectedLoaderVersion = ""
            return
        }

        if selectedMirrorSource == .fastMirror {
            if !versions.contains(selectedLoaderVersion) {
                selectedLoaderVersion = versions.first ?? ""
            }
            return
        }
        if selectedMirrorSource == .custom {
            if !versions.contains(selectedLoaderVersion) {
                selectedLoaderVersion = versions.first ?? ""
            }
            await updateCustomMirrorDetail()
            return
        }

        switch type {
        case .fabric:
            if let stable = try? await ServerDownloadService.latestStableFabricLoaderVersion(gameVersion: gameVersion),
               versions.contains(stable) {
                selectedLoaderVersion = stable
            } else if !versions.contains(selectedLoaderVersion) {
                selectedLoaderVersion = versions.first ?? ""
            }
        case .forge:
            if let stable = try? await ServerDownloadService.latestStableForgeVersion(gameVersion: gameVersion),
               versions.contains(stable) {
                selectedLoaderVersion = stable
            } else if !versions.contains(selectedLoaderVersion) {
                selectedLoaderVersion = versions.first ?? ""
            }
        default:
            if !versions.contains(selectedLoaderVersion) {
                selectedLoaderVersion = versions.first ?? ""
            }
        }
        updateParentState()
    }

    private func updateCustomMirrorDetail() async {
        guard selectedMirrorSource == .custom,
              let config = selectedCustomConfig,
              let baseURL = mirrorBaseURL(),
              !selectedFastMirrorCoreName.isEmpty,
              !selectedGameVersion.isEmpty,
              !selectedLoaderVersion.isEmpty else {
            await MainActor.run {
                selectedMirrorDownloadURL = ""
                selectedMirrorFileName = ""
            }
            return
        }
        do {
            let detail = try await CustomMirrorService.fetchCoreDetail(
                config: config,
                baseURL: baseURL,
                coreName: selectedFastMirrorCoreName,
                gameVersion: selectedGameVersion,
                coreVersion: selectedLoaderVersion
            )
            await MainActor.run {
                selectedMirrorDownloadURL = detail.downloadURL
                selectedMirrorFileName = detail.filename
            }
            updateParentState()
        } catch {
            Logger.shared.error("获取镜像下载信息失败: \(error.localizedDescription)")
            await MainActor.run {
                selectedMirrorDownloadURL = ""
                selectedMirrorFileName = ""
            }
            updateParentState()
        }
    }

    func handleFastMirrorCoreChange(_ newCoreName: String) {
        selectedFastMirrorCoreName = newCoreName
        if selectedMirrorSource == .fastMirror,
           let mapped = FastMirrorService.serverType(for: newCoreName) {
            selectedServerType = mapped
        }
        selectedGameVersion = ""
        selectedLoaderVersion = ""
        availableLoaderVersions = []
        if selectedMirrorSource == .custom {
            selectedMirrorDownloadURL = ""
            selectedMirrorFileName = ""
        }
        updateParentState()
        Task {
            await refreshAvailableVersions(for: selectedServerType)
        }
    }

    private func loadFastMirrorCores() async {
        do {
            let cores = try await FastMirrorService.fetchCores(baseURL: mirrorBaseURL())
            let filtered = cores
            await MainActor.run {
                fastMirrorCores = filtered
                if selectedFastMirrorCoreName.isEmpty, let first = filtered.first?.name {
                    handleFastMirrorCoreChange(first)
                } else if !selectedFastMirrorCoreName.isEmpty,
                          !filtered.contains(where: { $0.name == selectedFastMirrorCoreName }),
                          let first = filtered.first?.name {
                    handleFastMirrorCoreChange(first)
                }
            }
        } catch {
            Logger.shared.error("获取镜像核心失败: \(error.localizedDescription)")
            await MainActor.run {
                fastMirrorCores = []
                selectedFastMirrorCoreName = ""
            }
        }
    }

    private func loadCustomMirrorCores() async {
        guard let config = selectedCustomConfig,
              let baseURL = mirrorBaseURL() else {
            await MainActor.run {
                fastMirrorCores = []
                selectedFastMirrorCoreName = ""
            }
            return
        }
        do {
            let cores = try await CustomMirrorService.fetchCores(
                config: config,
                baseURL: baseURL
            )
            await MainActor.run {
                fastMirrorCores = cores
                if selectedFastMirrorCoreName.isEmpty, let first = cores.first?.name {
                    handleFastMirrorCoreChange(first)
                } else if !selectedFastMirrorCoreName.isEmpty,
                          !cores.contains(where: { $0.name == selectedFastMirrorCoreName }),
                          let first = cores.first?.name {
                    handleFastMirrorCoreChange(first)
                }
            }
        } catch {
            Logger.shared.error("获取镜像核心失败: \(error.localizedDescription)")
            await MainActor.run {
                fastMirrorCores = []
                selectedFastMirrorCoreName = ""
            }
        }
    }

    func handlePolarsCoreTypeChange(_ typeId: Int) {
        selectedPolarsCoreTypeId = typeId
        selectedPolarsCoreItemName = ""
        selectedMirrorDownloadURL = ""
        polarsCoreItems = []
        updateParentState()
        Task { await loadPolarsCoreItems(typeId: typeId) }
    }

    func handlePolarsCoreItemChange(_ item: PolarsMirrorService.CoreItem) {
        selectedPolarsCoreItemName = item.name
        selectedMirrorDownloadURL = item.downloadURL
        selectedMirrorFileName = item.name
        updateParentState()
    }

    private func loadPolarsCoreTypes() async {
        do {
            let types = try await PolarsMirrorService.fetchCoreTypes(baseURL: mirrorBaseURL())
            await MainActor.run {
                polarsCoreTypes = types
                if selectedPolarsCoreTypeId == nil, let first = types.first?.id {
                    handlePolarsCoreTypeChange(first)
                }
            }
        } catch {
            Logger.shared.error("获取极星核心类型失败: \(error.localizedDescription)")
            await MainActor.run {
                polarsCoreTypes = []
                selectedPolarsCoreTypeId = nil
            }
        }
    }

    private func loadPolarsCoreItems(typeId: Int) async {
        do {
            let items = try await PolarsMirrorService.fetchCoreItems(
                coreTypeId: typeId,
                baseURL: mirrorBaseURL()
            )
            await MainActor.run {
                polarsCoreItems = items
                if selectedPolarsCoreItemName.isEmpty, let first = items.first {
                    handlePolarsCoreItemChange(first)
                }
            }
        } catch {
            Logger.shared.error("获取极星核心列表失败: \(error.localizedDescription)")
            await MainActor.run {
                polarsCoreItems = []
                selectedPolarsCoreItemName = ""
                selectedMirrorDownloadURL = ""
            }
        }
    }

    private func resetMirrorSelections() {
        selectedFastMirrorCoreName = ""
        fastMirrorCores = []
        selectedPolarsCoreTypeId = nil
        polarsCoreTypes = []
        polarsCoreItems = []
        selectedPolarsCoreItemName = ""
        selectedMirrorDownloadURL = ""
        selectedMirrorFileName = ""
    }

    private func decodeCustomConfig(from json: String?) -> MirrorCustomAPIConfig? {
        guard let json, !json.isEmpty,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MirrorCustomAPIConfig.self, from: data)
    }

    private func mirrorBaseURL() -> URL? {
        let trimmed = selectedMirrorBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    func resolvedServerType() -> ServerType {
        if selectedMirrorSource == .fastMirror,
           let mapped = FastMirrorService.serverType(for: selectedFastMirrorCoreName) {
            return mapped
        }
        if selectedMirrorSource == .polars,
           let type = polarsCoreTypes.first(where: { $0.id == selectedPolarsCoreTypeId })?.name,
           let mapped = FastMirrorService.serverType(for: type) {
            return mapped
        }
        return selectedServerType
    }
}
