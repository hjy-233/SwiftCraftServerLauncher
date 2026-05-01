import SwiftUI

enum ResourceInstallTargetMode: String, CaseIterable, Identifiable {
    case game
    case server

    var id: String { rawValue }
}

private extension ServerInstance {
    var asGameVersionInfo: GameVersionInfo {
        GameVersionInfo(
            gameName: name,
            gameIcon: "",
            gameVersion: gameVersion,
            modVersion: loaderVersion,
            assetIndex: gameVersion,
            modLoader: serverType.rawValue
        )
    }
}

struct GlobalResourceSheet: View {
    let project: ModrinthProject
    let resourceType: String
    @Binding var isPresented: Bool
    let preloadedDetail: ModrinthProjectDetail?
    let preloadedCompatibleGames: [GameVersionInfo]
    let preloadedCompatibleServers: [ServerInstance]
    @EnvironmentObject var gameRepository: GameRepository
    @State private var selectedTargetMode: ResourceInstallTargetMode = .game
    @State private var selectedGame: GameVersionInfo?
    @State private var selectedServer: ServerInstance?
    @State private var selectedVersion: ModrinthProjectDetailVersion?
    @State private var availableVersions: [ModrinthProjectDetailVersion] = []
    @State private var dependencyState = DependencyState()
    @State private var isDownloadingAll = false
    @State private var isDownloadingMainOnly = false
    @State private var mainVersionId = ""

    private var canSelectServerTarget: Bool {
        resourceType.lowercased() == "mod" || resourceType.lowercased() == "plugin"
    }

    private var canSelectGameTarget: Bool {
        resourceType.lowercased() != "plugin"
    }

    private var hasGameTargets: Bool {
        !preloadedCompatibleGames.isEmpty && canSelectGameTarget
    }

    private var hasServerTargets: Bool {
        !preloadedCompatibleServers.isEmpty && canSelectServerTarget
    }

    private var hasAnyTarget: Bool {
        hasGameTargets || hasServerTargets
    }

    private var selectedTargetTitle: String {
        if selectedTargetMode == .server {
            return selectedServer?.name ?? "global_resource.add".localized()
        }
        return selectedGame?.gameName ?? "global_resource.add".localized()
    }

    private var selectedGameForVersionPickerBinding: Binding<GameVersionInfo?> {
        Binding(
            get: {
                if selectedTargetMode == .server {
                    return selectedServer?.asGameVersionInfo
                }
                return selectedGame
            },
            set: { _ in }
        )
    }

    var body: some View {
        CommonSheetView(
            header: {
                Text(selectedTargetTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            },
            body: {
                if let detail = preloadedDetail {
                    if !hasAnyTarget {
                        Text("No compatible targets")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        VStack(alignment: .leading) {
                            ModrinthProjectTitleView(projectDetail: detail)
                                .padding(.bottom, 18)

                            if hasGameTargets && hasServerTargets {
                                Picker("Target", selection: $selectedTargetMode) {
                                    Text("Game").tag(ResourceInstallTargetMode.game)
                                    Text("Server").tag(ResourceInstallTargetMode.server)
                                }
                                .pickerStyle(.segmented)
                            }

                            if selectedTargetMode == .server {
                                Picker("Server", selection: $selectedServer) {
                                    Text("Please select server").tag(ServerInstance?.none)
                                    ForEach(preloadedCompatibleServers, id: \.id) { server in
                                        Text("\(server.name) - \(server.gameVersion) - \(server.serverType.displayName)")
                                            .tag(Optional(server))
                                    }
                                }
                                .pickerStyle(.menu)
                            } else {
                                CommonSheetGameBody(
                                    compatibleGames: preloadedCompatibleGames,
                                    selectedGame: $selectedGame
                                )
                            }

                            if (selectedTargetMode == .game && selectedGame != nil)
                                || (selectedTargetMode == .server && selectedServer != nil) {
                                spacerView()
                                VersionPickerForSheet(
                                    project: project,
                                    resourceType: resourceType,
                                    selectedGame: selectedGameForVersionPickerBinding,
                                    selectedVersion: $selectedVersion,
                                    availableVersions: $availableVersions,
                                    mainVersionId: $mainVersionId
                                ) { version in
                                    if resourceType == "mod",
                                        selectedTargetMode == .game,
                                        version != nil,
                                        let game = selectedGame {
                                        loadDependencies(for: game)
                                    } else {
                                        dependencyState = DependencyState()
                                    }
                                }
                                if resourceType == "mod", selectedTargetMode == .game {
                                    if dependencyState.isLoading || !dependencyState.dependencies.isEmpty {
                                        spacerView()
                                        DependencySectionView(state: $dependencyState)
                                    }
                                }
                            }
                        }
                    }
                }
            },
            footer: {
                GlobalResourceFooter(
                    project: project,
                    resourceType: resourceType,
                    isPresented: $isPresented,
                    projectDetail: preloadedDetail,
                    selectedGame: selectedGame,
                    selectedServer: selectedServer,
                    installToServer: selectedTargetMode == .server,
                    selectedVersion: selectedVersion,
                    dependencyState: dependencyState,
                    isDownloadingAll: $isDownloadingAll,
                    isDownloadingMainOnly: $isDownloadingMainOnly,
                    gameRepository: gameRepository,
                    mainVersionId: $mainVersionId,
                    compatibleGames: preloadedCompatibleGames
                )
            }
        )
        .onAppear {
            initializeDefaultTargetSelection()
        }
        .onChange(of: selectedTargetMode) { _, _ in
            selectedVersion = nil
            availableVersions = []
            dependencyState = DependencyState()
            mainVersionId = ""
        }
        .onChange(of: selectedGame?.id) { _, _ in
            selectedVersion = nil
            availableVersions = []
            dependencyState = DependencyState()
            mainVersionId = ""
        }
        .onChange(of: selectedServer?.id) { _, _ in
            selectedVersion = nil
            availableVersions = []
            dependencyState = DependencyState()
            mainVersionId = ""
        }
        .onDisappear {
            selectedGame = nil
            selectedServer = nil
            selectedVersion = nil
            availableVersions = []
            dependencyState = DependencyState()
            isDownloadingAll = false
            isDownloadingMainOnly = false
            mainVersionId = ""
        }
    }

    private func initializeDefaultTargetSelection() {
        if hasServerTargets && !hasGameTargets {
            selectedTargetMode = .server
        } else {
            selectedTargetMode = .game
        }
        if selectedGame == nil {
            selectedGame = preloadedCompatibleGames.first
        }
        if selectedServer == nil {
            selectedServer = preloadedCompatibleServers.first
        }
    }

    private func loadDependencies(for game: GameVersionInfo) {
        dependencyState.isLoading = true
        Task {
            do {
                try await loadDependenciesThrowing(game: game)
            } catch {
                let globalError = GlobalError.from(error)
                Logger.shared.error("加载依赖项失败: \(globalError.chineseMessage)")
                GlobalErrorHandler.shared.handle(globalError)
                _ = await MainActor.run {
                    dependencyState = DependencyState()
                }
            }
        }
    }

    private func loadDependenciesThrowing(game: GameVersionInfo) async throws {
        guard !project.projectId.isEmpty else {
            throw GlobalError.validation(
                chineseMessage: "项目ID不能为空",
                i18nKey: "error.validation.project_id_empty",
                level: .notification
            )
        }

        let missingWithVersions = await ModrinthDependencyDownloader
            .getMissingDependenciesWithVersions(
                for: project.projectId,
                gameInfo: game
            )

        var depVersions: [String: [ModrinthProjectDetailVersion]] = [:]
        var depSelected: [String: ModrinthProjectDetailVersion?] = [:]
        var dependencies: [ModrinthProjectDetail] = []

        for (detail, versions) in missingWithVersions {
            dependencies.append(detail)
            depVersions[detail.id] = versions
            depSelected[detail.id] = versions.first
        }

        _ = await MainActor.run {
            dependencyState = DependencyState(
                dependencies: dependencies,
                versions: depVersions,
                selected: depSelected,
                isLoading: false
            )
        }
    }
}
