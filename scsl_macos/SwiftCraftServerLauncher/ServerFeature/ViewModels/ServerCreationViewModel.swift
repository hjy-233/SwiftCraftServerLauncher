import SwiftUI
import Combine
import UniformTypeIdentifiers

@MainActor
class ServerCreationViewModel: ObservableObject {
    @Published var isDownloading: Bool = false
    @Published var isFormValid: Bool = false
    @Published var triggerConfirm: Bool = false
    @Published var triggerCancel: Bool = false

    @Published var selectedServerType: ServerType = .vanilla
    @Published var selectedServerIcon: String = "server.rack"
    @Published var selectedServerIconURL: URL?
    @Published var selectedGameVersion: String = ""
    @Published var versionTime: String = ""
    @Published var selectedLoaderVersion: String = ""
    @Published var availableLoaderVersions: [String] = []
    @Published var availableVersions: [String] = []
    @Published var selectedMirrorSource: ServerMirrorSource = .official
    @Published var selectedMirrorSourceId: String = ServerMirrorSource.official.id
    @Published var selectedMirrorDisplayName: String = ServerMirrorSource.official.displayName
    @Published var selectedMirrorBaseURL: String = ""
    @Published var fastMirrorCores: [FastMirrorService.CoreSummary] = []
    @Published var selectedFastMirrorCoreName: String = ""
    @Published var polarsCoreTypes: [PolarsMirrorService.CoreType] = []
    @Published var selectedPolarsCoreTypeId: Int?
    @Published var polarsCoreItems: [PolarsMirrorService.CoreItem] = []
    @Published var selectedPolarsCoreItemName: String = ""
    @Published var selectedMirrorDownloadURL: String = ""
    @Published var selectedMirrorFileName: String = ""

    @Published var customJarURL: URL?
    @Published var hasAcceptedEula: Bool = false
    @Published var consoleMode: ServerConsoleMode = .direct
    @Published var rconPortText: String = "25575"
    @Published var rconPassword: String = ""
    @Published private(set) var isRemoteNode: Bool = false

    let serverSetupService = ServerSetupUtil()
    let serverNameValidator: ServerNameValidator

    private var serverRepository: ServerRepository?
    private var didInit = false
    private var isSubmitting = false
    private var cancellables = Set<AnyCancellable>()
    private let configuration: GameFormConfiguration
    private let selectedNode: ServerNode
    var selectedCustomConfig: MirrorCustomAPIConfig?

    init(configuration: GameFormConfiguration, selectedNode: ServerNode = .local) {
        self.configuration = configuration
        self.selectedNode = selectedNode
        self.isRemoteNode = !selectedNode.isLocal
        self.serverNameValidator = ServerNameValidator(serverSetupService: serverSetupService)
        setupObservers()
        updateParentState()
    }

    private func setupObservers() {
        serverNameValidator.objectWillChange
            .sink { [weak self] in
                DispatchQueue.main.async {
                    self?.updateParentState()
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        serverSetupService.objectWillChange
            .sink { [weak self] in
                DispatchQueue.main.async {
                    self?.updateParentState()
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)
    }

    func setup(serverRepository: ServerRepository) {
        self.serverRepository = serverRepository
        if !didInit {
            didInit = true
            Task { await initializeVersionPicker() }
        }
        updateParentState()
    }

    func handleConfirm() {
        configuration.actions.onConfirm()
        Task { await performConfirmAction() }
    }

    func handleCancel() {
        configuration.actions.onCancel()
    }

    func updateParentState() {
        let newIsDownloading = serverSetupService.downloadState.isDownloading
        let newIsFormValid = computeIsFormValid()

        DispatchQueue.main.async { [weak self] in
            self?.configuration.isDownloading.wrappedValue = newIsDownloading
            self?.configuration.isFormValid.wrappedValue = newIsFormValid
            self?.isDownloading = newIsDownloading
            self?.isFormValid = newIsFormValid
        }
    }

    private func computeIsFormValid() -> Bool {
        if !serverNameValidator.isFormValid { return false }
        if selectedMirrorSource == .fastMirror, selectedServerType != .custom {
            return !selectedFastMirrorCoreName.isEmpty && !selectedGameVersion.isEmpty && !selectedLoaderVersion.isEmpty
        }
        if selectedMirrorSource == .custom {
            return !selectedFastMirrorCoreName.isEmpty
                && !selectedGameVersion.isEmpty
                && !selectedLoaderVersion.isEmpty
                && !selectedMirrorDownloadURL.isEmpty
                && !selectedMirrorFileName.isEmpty
        }
        if selectedMirrorSource == .polars {
            return selectedPolarsCoreTypeId != nil && !selectedPolarsCoreItemName.isEmpty && !selectedMirrorDownloadURL.isEmpty
        }
        switch selectedServerType {
        case .custom:
            return customJarURL != nil
        case .fabric, .forge:
            return !selectedGameVersion.isEmpty && !selectedLoaderVersion.isEmpty
        case .vanilla, .paper:
            return !selectedGameVersion.isEmpty
        }
    }

    private func performConfirmAction() async {
        if isSubmitting { return }
        isSubmitting = true
        let spinnerWatchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            await MainActor.run {
                guard let self, self.isSubmitting else { return }
                self.serverSetupService.downloadState.reset()
                self.serverSetupService.downloadState.isDownloading = false
                self.isSubmitting = false
                self.updateParentState()
                Logger.shared.warning("服务器创建超时，自动结束加载状态")
            }
        }
        defer {
            spinnerWatchdog.cancel()
            isSubmitting = false
        }

        guard let serverRepository = serverRepository else { return }
        let name = serverNameValidator.serverName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let isDuplicate = await serverSetupService.checkServerNameDuplicate(name)
        if isDuplicate || serverRepository.getServerByName(by: name) != nil {
            handleDuplicateName()
            return
        }

        let serverUUID = UUID()
        let directoryName: String = {
            // Forge 26+ 在包含非 ASCII 的服务器目录名下会启动失败（Bad escape）。
            // 为了兼容中文服务器名，Forge 默认使用 UUID 作为目录名。
            if selectedNode.isLocal, selectedServerType == .forge {
                return serverUUID.uuidString
            }
            return name
        }()

        do {
            await MainActor.run {
                serverSetupService.downloadState.reset()
                serverSetupService.downloadState.isDownloading = true
            }
            defer {
                self.serverSetupService.downloadState.reset()
                self.serverSetupService.downloadState.isDownloading = false
                self.updateParentState()
            }

            var serverJar = "server.jar"
            let javaPath: String
            let iconImageFileName: String?
            if selectedNode.isLocal {
                let serverDir = try serverSetupService.createServerDirectory(name: directoryName)
                iconImageFileName = try persistServerIconIfNeeded(serverName: name, baseDirectory: serverDir)
                if selectedServerType == .custom, let url = customJarURL {
                    guard url.startAccessingSecurityScopedResource() else {
                        throw GlobalError.fileSystem(
                            chineseMessage: "无法访问自定义 Jar 文件",
                            i18nKey: "error.filesystem.file_access_failed",
                            level: .notification
                        )
                    }
                    defer { url.stopAccessingSecurityScopedResource() }
                    serverJar = try serverSetupService.copyCustomJar(from: url, to: serverDir)
                    // 自定义 Jar 不强依赖版本元数据，延迟到启动时再解析/回退 Java。
                    javaPath = ""
                } else {
                    if selectedMirrorSource == .polars || selectedMirrorSource == .custom {
                        serverJar = try await ServerDownloadService.downloadMirrorJar(
                            downloadURL: selectedMirrorDownloadURL,
                            fileName: selectedMirrorFileName,
                            serverDir: serverDir
                        )
                        javaPath = ""
                    } else {
                        serverJar = try await ServerDownloadService.downloadServerJar(
                            serverType: selectedServerType,
                            gameVersion: selectedGameVersion,
                            loaderVersion: selectedLoaderVersion,
                            serverDir: serverDir,
                            mirror: ServerDownloadService.MirrorDownloadOptions(
                                source: selectedMirrorSource,
                                coreName: selectedFastMirrorCoreName,
                                fileName: selectedMirrorFileName,
                                downloadURL: selectedMirrorDownloadURL,
                                baseURL: selectedMirrorBaseURL
                            )
                        )
                        let javaVersion = try await ServerDownloadService.resolveJavaVersion(gameVersion: selectedGameVersion)
                        javaPath = await JavaManager.shared.ensureJavaExists(
                            version: javaVersion.component,
                            minimumMajorVersion: javaVersion.majorVersion
                        )
                    }
                }
                if hasAcceptedEula {
                    try serverSetupService.acceptEula(in: serverDir)
                }

                if selectedServerType == .forge {
                    let tempServer = ServerInstance(
                        id: serverUUID,
                        name: name,
                        directoryName: directoryName,
                        serverType: selectedServerType,
                        gameVersion: selectedGameVersion,
                        loaderVersion: selectedLoaderVersion,
                        serverJar: serverJar,
                        javaPath: javaPath,
                        nodeId: selectedNode.id
                    )
                    try await ForgeInstallerService.install(server: tempServer, serverDir: serverDir)
                }
            } else {
                let localRemoteServerDir = AppPaths.remoteNodeServersDirectory(nodeId: selectedNode.id)
                    .appendingPathComponent(name, isDirectory: true)
                try? FileManager.default.createDirectory(at: localRemoteServerDir, withIntermediateDirectories: true)
                iconImageFileName = try persistServerIconIfNeeded(serverName: name, baseDirectory: localRemoteServerDir)
                if selectedServerType == .custom {
                    throw GlobalError.validation(
                        chineseMessage: "远程节点暂不支持上传自定义 Jar",
                        i18nKey: "error.validation.server_not_selected",
                        level: .notification
                    )
                }
                if selectedServerType == .forge {
                    throw GlobalError.validation(
                        chineseMessage: "远程节点暂不支持 Forge 安装流程",
                        i18nKey: "error.validation.server_not_selected",
                        level: .notification
                    )
                }
                let target = try await ServerDownloadService.resolveDownloadTargetForRemote(
                    serverType: selectedServerType,
                    gameVersion: selectedGameVersion,
                    loaderVersion: selectedLoaderVersion,
                    mirror: ServerDownloadService.MirrorDownloadOptions(
                        source: selectedMirrorSource,
                        coreName: selectedFastMirrorCoreName,
                        fileName: selectedMirrorFileName,
                        downloadURL: selectedMirrorDownloadURL,
                        baseURL: selectedMirrorBaseURL
                    )
                )
                let alreadyPrepared = await SSHNodeService.waitForRemoteServerJar(
                    node: selectedNode,
                    serverName: name,
                    expectedJarName: target.fileName,
                    timeoutSeconds: 4,
                    pollIntervalSeconds: 2
                )

                if !alreadyPrepared {
                    _ = await prepareRemoteServerWithTimeout(
                        node: selectedNode,
                        serverName: name,
                        target: target
                    )
                }

                let hasJar = await SSHNodeService.waitForRemoteServerJar(
                    node: selectedNode,
                    serverName: name,
                    expectedJarName: target.fileName,
                    timeoutSeconds: 12,
                    pollIntervalSeconds: 2
                )
                guard hasJar else {
                    throw GlobalError.validation(
                        chineseMessage: "远程目录未检测到 Jar，请检查节点路径与下载权限",
                        i18nKey: "error.validation.server_not_selected",
                        level: .notification
                    )
                }
                serverJar = target.fileName
                javaPath = "java"
            }

            let server = ServerInstance(
                id: serverUUID,
                name: name,
                directoryName: directoryName,
                iconName: selectedServerIcon,
                iconImageFileName: iconImageFileName,
                serverType: resolvedServerType(),
                gameVersion: selectedGameVersion,
                loaderVersion: selectedLoaderVersion,
                serverJar: serverJar,
                javaPath: javaPath,
                nodeId: selectedNode.id,
                consoleMode: consoleMode,
                rconPort: Int(rconPortText) ?? 25575,
                rconPassword: rconPassword.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            serverRepository.addServerSilently(server)
        } catch {
            if selectedNode.isLocal {
                let serverDir = AppPaths.serverDirectory(serverName: directoryName)
                if FileManager.default.fileExists(atPath: serverDir.path) {
                    try? FileManager.default.removeItem(at: serverDir)
                }
            }
            GlobalErrorHandler.shared.handle(error)
        }
    }

    private func persistServerIconIfNeeded(serverName: String, baseDirectory: URL) throws -> String? {
        guard let selectedServerIconURL else {
            return nil
        }
        let didAccessSecurityScoped = selectedServerIconURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScoped {
                selectedServerIconURL.stopAccessingSecurityScopedResource()
            }
        }

        let ext = selectedServerIconURL.pathExtension.isEmpty ? "png" : selectedServerIconURL.pathExtension.lowercased()
        let fileName = ".scsl-server-icon.\(ext)"
        let destination = baseDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: selectedServerIconURL, to: destination)
        return fileName
    }

    private func prepareRemoteServerWithTimeout(
        node: ServerNode,
        serverName: String,
        target: ServerDownloadService.DownloadTarget
    ) async -> Bool {
        let timeoutSeconds: UInt64 = 20
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                do {
                    try await SSHNodeService.prepareRemoteServerDirectoryAndDownload(
                        node: node,
                        serverName: serverName,
                        target: target
                    )
                    return true
                } catch {
                    let message = GlobalError.from(error).chineseMessage
                    Logger.shared.warning("远程下载异常，转入目录检测: \(message)")
                    return false
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                Logger.shared.warning("远程下载确认超时，转入目录检测: \(serverName)")
                return false
            }

            if let result = await group.next() {
                group.cancelAll()
                return result
            }
            return false
        }
    }

    private func handleDuplicateName() {
        let error = GlobalError.validation(
            chineseMessage: "服务器名称已存在",
            i18nKey: "error.validation.server_name_duplicate",
            level: .notification
        )
        Logger.shared.error(error.chineseMessage)
        GlobalErrorHandler.shared.handle(error)
    }

    func initializeVersionPicker() async {
        await refreshAvailableVersions(for: selectedServerType)
    }

    func updateAvailableVersions(_ versions: [String]) async {
        self.availableVersions = versions
        if !versions.contains(self.selectedGameVersion) && !versions.isEmpty {
            self.selectedGameVersion = versions.first ?? ""
        }

        if !versions.isEmpty {
            if selectedMirrorSource == .fastMirror || selectedMirrorSource == .custom {
                self.versionTime = ""
            } else {
                let targetVersion = versions.contains(self.selectedGameVersion) ? self.selectedGameVersion : (versions.first ?? "")
                let timeString = await ModrinthService.queryVersionTime(from: targetVersion)
                self.versionTime = timeString
            }
        }
        updateParentState()
    }
}
