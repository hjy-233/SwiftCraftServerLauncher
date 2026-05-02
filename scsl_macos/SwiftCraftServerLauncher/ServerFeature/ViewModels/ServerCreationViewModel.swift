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
            guard selectedNode.isLocal else {
                throw GlobalError.validation(
                    chineseMessage: "远程节点建服功能已停用，请使用本地节点",
                    i18nKey: "error.validation.server_not_selected",
                    level: .notification
                )
            }
            await MainActor.run {
                serverSetupService.downloadState.reset()
                serverSetupService.downloadState.isDownloading = true
            }
            defer {
                self.serverSetupService.downloadState.reset()
                self.serverSetupService.downloadState.isDownloading = false
                self.updateParentState()
            }

            let iconImageFileName: String?
            let serverDir = try serverSetupService.createServerDirectory(name: directoryName)
            iconImageFileName = try persistServerIconIfNeeded(serverName: name, baseDirectory: serverDir)
            let creation = try await createLocalServer(
                serverUUID: serverUUID,
                name: name,
                directoryName: directoryName,
                iconImageFileName: iconImageFileName
            )
            Logger.shared.info("本地服务器创建完成: \(creation.id) / \(creation.serverJar)")

            serverRepository.reloadServers()
        } catch {
            let serverDir = AppPaths.serverDirectory(serverName: directoryName)
            if FileManager.default.fileExists(atPath: serverDir.path) {
                try? FileManager.default.removeItem(at: serverDir)
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

    private func createLocalServer(
        serverUUID: UUID,
        name: String,
        directoryName: String,
        iconImageFileName: String?
    ) async throws -> LocalServerCreateResponse {
        let source = try await buildLocalCreateSource()
        let javaPath = try await resolveLocalJavaPath()
        let request = LocalServerCreateRequest(
            id: serverUUID.uuidString,
            name: name,
            directoryName: directoryName,
            iconName: selectedServerIcon,
            iconImageFileName: iconImageFileName,
            serverType: resolvedServerType(),
            gameVersion: selectedGameVersion,
            loaderVersion: selectedLoaderVersion,
            launchCommand: "",
            javaPath: javaPath,
            jvmArguments: "",
            xms: 0,
            xmx: 0,
            consoleMode: consoleMode,
            rconPort: Int(rconPortText) ?? 25575,
            rconPassword: rconPassword.trimmingCharacters(in: .whitespacesAndNewlines),
            acceptEula: hasAcceptedEula,
            source: source
        )
        return try await ServerCreationCoreService.createLocal(request: request)
    }

    private func buildLocalCreateSource() async throws -> LocalServerCreateSource {
        if selectedServerType == .custom, let url = customJarURL {
            guard url.startAccessingSecurityScopedResource() else {
                throw GlobalError.fileSystem(
                    chineseMessage: "无法访问自定义 Jar 文件",
                    i18nKey: "error.filesystem.file_access_failed",
                    level: .notification
                )
            }
            defer { url.stopAccessingSecurityScopedResource() }
            return .customJar(sourcePath: url.path)
        }

        if selectedMirrorSource == .polars || selectedMirrorSource == .custom {
            return .download(
                url: selectedMirrorDownloadURL,
                fileName: selectedMirrorFileName,
                sha1: nil
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
        return .download(
            url: target.url.absoluteString,
            fileName: target.fileName,
            sha1: target.sha1
        )
    }

    private func resolveLocalJavaPath() async throws -> String {
        if selectedServerType == .custom || selectedMirrorSource == .polars || selectedMirrorSource == .custom {
            return ""
        }
        let javaVersion = try await ServerDownloadService.resolveJavaVersion(gameVersion: selectedGameVersion)
        return await JavaManager.shared.ensureJavaExists(
            version: javaVersion.component,
            minimumMajorVersion: javaVersion.majorVersion
        )
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
