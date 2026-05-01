import SwiftUI

struct GlobalResourceFooter: View {
    let project: ModrinthProject
    let resourceType: String
    @Binding var isPresented: Bool
    let projectDetail: ModrinthProjectDetail?
    let selectedGame: GameVersionInfo?
    let selectedServer: ServerInstance?
    let installToServer: Bool
    let selectedVersion: ModrinthProjectDetailVersion?
    let dependencyState: DependencyState
    @Binding var isDownloadingAll: Bool
    @Binding var isDownloadingMainOnly: Bool
    let gameRepository: GameRepository
    @Binding var mainVersionId: String
    let compatibleGames: [GameVersionInfo]

    var body: some View {
        Group {
            if projectDetail != nil {
                if compatibleGames.isEmpty && !installToServer {
                    HStack {
                        Spacer()
                        Button("common.close".localized()) { isPresented = false }
                    }
                } else {
                    HStack {
                        if isDownloadingAll || isDownloadingMainOnly {
                            Button {
                                isPresented = false
                            } label: {
                            Label("download.minimize".localized(), systemImage: "minus.square")
                            }
                            .buttonStyle(.borderless)
                        }
                        Button("common.close".localized()) { isPresented = false }
                        Spacer()
                        if resourceType == "mod" && !installToServer {
                            if !dependencyState.isLoading, selectedVersion != nil {
                                Button(action: downloadAllManual) {
                                    if isDownloadingAll {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Text("global_resource.download_all".localized())
                                    }
                                }
                                .disabled(isDownloadingAll)
                                .keyboardShortcut(.defaultAction)
                            }
                        } else if selectedVersion != nil {
                            Button(action: downloadResource) {
                                if isDownloadingAll {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text("global_resource.download".localized())
                                }
                            }
                            .disabled(isDownloadingAll)
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                }
            } else {
                HStack {
                    Spacer()
                    Button("common.close".localized()) { isPresented = false }
                }
            }
        }
    }

    private func downloadAllManual() {
        guard let game = selectedGame, selectedVersion != nil else { return }
        isDownloadingAll = true
        Task {
            do {
                try await downloadAllManualThrowing(game: game)
            } catch {
                let globalError = GlobalError.from(error)
                Logger.shared.error("手动下载所有依赖项失败: \(globalError.chineseMessage)")
                GlobalErrorHandler.shared.handle(globalError)
            }
            _ = await MainActor.run {
                isDownloadingAll = false
                isPresented = false
            }
        }
    }

    private func downloadAllManualThrowing(game: GameVersionInfo) async throws {
        guard !project.projectId.isEmpty else {
            throw GlobalError.validation(
                chineseMessage: "项目ID不能为空",
                i18nKey: "error.validation.project_id_empty",
                level: .notification
            )
        }

        let success = await ModrinthDependencyDownloader.downloadManualDependenciesAndMain(
            dependencies: dependencyState.dependencies,
            selectedVersions: dependencyState.selected.compactMapValues { $0?.id },
            dependencyVersions: dependencyState.versions,
            mainProjectId: project.projectId,
            mainProjectVersionId: mainVersionId.isEmpty ? nil : mainVersionId,
            gameInfo: game,
            query: resourceType,
            gameRepository: gameRepository,
            onDependencyDownloadStart: { _ in },
            onDependencyDownloadFinish: { _, _ in }
        )

        if !success {
            throw GlobalError.download(
                chineseMessage: "手动下载依赖项失败",
                i18nKey: "error.download.manual_dependencies_failed",
                level: .notification
            )
        }
    }

    private func downloadResource() {
        guard selectedVersion != nil else { return }
        isDownloadingAll = true
        Task {
            do {
                try await downloadResourceThrowing()
            } catch {
                let globalError = GlobalError.from(error)
                Logger.shared.error("下载资源失败: \(globalError.chineseMessage)")
                GlobalErrorHandler.shared.handle(globalError)
            }
            _ = await MainActor.run {
                isDownloadingAll = false
                isPresented = false
            }
        }
    }

    private func downloadResourceThrowing() async throws {
        guard !project.projectId.isEmpty else {
            throw GlobalError.validation(
                chineseMessage: "项目ID不能为空",
                i18nKey: "error.validation.project_id_empty",
                level: .notification
            )
        }

        if installToServer {
            guard let server = selectedServer else {
                throw GlobalError.validation(
                    chineseMessage: "请选择服务器",
                    i18nKey: "error.validation.server_not_selected",
                    level: .notification
                )
            }
            let success = await downloadMainResourceToServer(server: server)
            if !success {
                throw GlobalError.download(
                    chineseMessage: "下载资源失败",
                    i18nKey: "error.download.resource_download_failed",
                    level: .notification
                )
            }
            return
        }

        guard let game = selectedGame else {
            throw GlobalError.validation(
                chineseMessage: "请选择游戏",
                i18nKey: "error.validation.game_not_selected",
                level: .notification
            )
        }
        let (success, _, _) = await ModrinthDependencyDownloader.downloadMainResourceOnly(
            mainProjectId: project.projectId,
            gameInfo: game,
            query: resourceType,
            gameRepository: gameRepository,
            filterLoader: true,
            mainProjectVersionId: mainVersionId.isEmpty ? nil : mainVersionId
        )

        if !success {
            throw GlobalError.download(
                chineseMessage: "下载资源失败",
                i18nKey: "error.download.resource_download_failed",
                level: .notification
            )
        }
    }

    private func downloadMainResourceToServer(server: ServerInstance) async -> Bool {
        do {
            let selectedLoaders = selectedLoadersFor(serverType: server.serverType)
            let versions = try await ModrinthService.fetchProjectVersionsFilter(
                id: project.projectId,
                selectedVersions: [server.gameVersion],
                selectedLoaders: selectedLoaders,
                type: resourceType
            )
            let targetVersion: ModrinthProjectDetailVersion?
            if !mainVersionId.isEmpty {
                targetVersion = versions.first { $0.id == mainVersionId }
            } else {
                targetVersion = versions.first
            }
            guard
                let version = targetVersion,
                let primaryFile = ModrinthService.filterPrimaryFiles(from: version.files)
            else {
                return false
            }
            let destinationDir: URL
            if resourceType.lowercased() == "plugin" {
                destinationDir = AppPaths.serverPluginsDirectory(serverName: server.name)
            } else if resourceType.lowercased() == "mod" {
                destinationDir = AppPaths.serverModsDirectory(serverName: server.name)
            } else {
                return false
            }
            try FileManager.default.createDirectory(
                at: destinationDir,
                withIntermediateDirectories: true
            )
            let destinationURL = destinationDir.appendingPathComponent(primaryFile.filename)
            _ = try await DownloadManager.downloadFile(
                urlString: primaryFile.url,
                destinationURL: destinationURL,
                expectedSha1: primaryFile.hashes.sha1
            )
            return true
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("下载服务器资源失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return false
        }
    }

    private func selectedLoadersFor(serverType: ServerType) -> [String] {
        switch serverType {
        case .paper:
            return ["paper", "bukkit", "spigot", "purpur", "folia"]
        case .fabric:
            return ["fabric"]
        case .forge:
            return ["forge"]
        default:
            return []
        }
    }
}
