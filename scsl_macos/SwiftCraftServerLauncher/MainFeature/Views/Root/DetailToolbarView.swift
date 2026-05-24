import SwiftUI

public struct DetailToolbarView: ToolbarContent {
    @Environment(\.openURL)
    private var openURL
    @ObservedObject var filterState: ResourceFilterState
    @ObservedObject var detailState: ResourceDetailState
    @ObservedObject var serverRepository: ServerRepository
    @ObservedObject var serverLaunchUseCase: ServerLaunchUseCase
    @StateObject private var serverActionManager = ServerActionManager.shared
    @StateObject private var serverStatusManager = ServerStatusManager.shared
    @StateObject private var toolbarSelection = ServerDetailToolbarSelectionState.shared

    init(
        filterState: ResourceFilterState,
        detailState: ResourceDetailState,
        serverRepository: ServerRepository,
        serverLaunchUseCase: ServerLaunchUseCase
    ) {
        self.filterState = filterState
        self.detailState = detailState
        self.serverRepository = serverRepository
        self.serverLaunchUseCase = serverLaunchUseCase
    }

    private var currentServer: ServerInstance? {
        if case .server(let serverId) = detailState.selectedItem {
            return serverRepository.getServer(by: serverId)
        }
        return nil
    }

    private func openCurrentResourceInBrowser() {
        guard let slug = detailState.loadedProjectDetail?.slug else { return }
        let baseURL = URLConfig.API.Modrinth.webProjectBase
        guard let url = URL(string: baseURL + slug) else { return }
        openURL(url)
    }

    private func post(_ action: ServerDetailToolbarAction) {
        ServerDetailToolbarActionBus.post(action)
    }

    private func launchSummaryLines(for server: ServerInstance) -> [String] {
        let javaPath = server.javaPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "java"
            : server.javaPath
        let jvmArgs = server.jvmArguments.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedJvm = jvmArgs.isEmpty ? "-" : jvmArgs
        let xmsText = server.xms > 0 ? "\(server.xms)M" : "-"
        let xmxText = server.xmx > 0 ? "\(server.xmx)M" : "-"
        return [
            "\( "server.runtime.java_path".localized() ): \(javaPath)",
            "\( "server.runtime.jvm".localized() ): \(resolvedJvm)",
            "\( "server.runtime.memory.xms".localized() ): \(xmsText)",
            "\( "server.runtime.memory.xmx".localized() ): \(xmxText)",
        ]
    }

    public var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            switch detailState.selectedItem {
            case .server:
                if let server = currentServer {
                    HStack(spacing: 4) {
                        Button {
                            Task {
                                let isRunning = serverStatusManager.isServerRunning(serverId: server.id)
                                if isRunning {
                                    await serverLaunchUseCase.stopServer(server: server)
                                } else {
                                    serverStatusManager.setServerLaunching(serverId: server.id, isLaunching: true)
                                    defer { serverStatusManager.setServerLaunching(serverId: server.id, isLaunching: false) }
                                    await serverLaunchUseCase.launchServer(server: server)
                                }
                            }
                        } label: {
                            let isRunning = serverStatusManager.isServerRunning(serverId: server.id)
                            let isLaunching = serverStatusManager.isServerLaunching(serverId: server.id)
                            if isLaunching && !isRunning {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: isRunning ? "stop.fill" : "play.fill")
                                    .imageScale(.medium)
                            }
                        }
                        .scaleEffect(serverStatusManager.isServerLaunching(serverId: server.id) ? 0.98 : 1.0)
                        .opacity(serverStatusManager.isServerLaunching(serverId: server.id) ? 0.88 : 1.0)
                        .animation(.easeInOut(duration: 0.15), value: serverStatusManager.isServerLaunching(serverId: server.id))
                        .disabled(serverStatusManager.isServerLaunching(serverId: server.id))
                        .applyReplaceTransition()

                        Menu {
                            Section("server.launch.title".localized()) {
                                ForEach(launchSummaryLines(for: server), id: \.self) { line in
                                    Text(line).disabled(true)
                                }
                            }
                            Divider()
                            Button("common.edit".localized()) {
                                detailState.showServerRuntimeSettingsSheet = true
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .imageScale(.small)
                                .frame(width: 12)
                                .padding(.vertical, 2)
                        }
                        .menuIndicator(.hidden)
                        .help("server.launch.title".localized())
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    if detailState.serverPanelSection == "console" {
                        Button {
                            serverActionManager.showInFinder(server: server)
                        } label: {
                            Label("game.path".localized(), systemImage: "folder")
                                .foregroundStyle(.primary)
                        }
                        .help("game.path".localized())
                    }

                    switch detailState.serverPanelSection {
                    case "serverConfig":
                        Button {
                            post(.configNewFile)
                        } label: {
                            Label("server.files.new_file".localized(), systemImage: "doc.badge.plus")
                        }
                        .help("server.files.new_file".localized())
                        Button {
                            post(.configNewFolder)
                        } label: {
                            Label("server.files.new_folder".localized(), systemImage: "folder.badge.plus")
                        }
                        .help("server.files.new_folder".localized())
                        Button {
                            post(.configUpload)
                        } label: {
                            Label("server.files.upload".localized(), systemImage: "tray.and.arrow.up")
                        }
                        .help("server.files.upload".localized())
                        Button {
                            post(.configRename)
                        } label: {
                            Label("server.files.rename".localized(), systemImage: "pencil")
                        }
                        .help("server.files.rename".localized())
                        Button {
                            post(.configDelete)
                        } label: {
                            Label("server.files.delete".localized(), systemImage: "trash")
                        }
                        .help("server.files.delete".localized())
                        Button {
                            post(.configToggleSidebar)
                        } label: {
                            Label("server.files.shortcut.sidebar".localized(), systemImage: "sidebar.left")
                        }
                        .help("server.files.shortcut.sidebar".localized())
                    case "worlds":
                        Button {
                            post(.worldsOpenFolder)
                        } label: {
                            Label("server.worlds.open_folder".localized(), systemImage: "folder")
                        }
                        .help("server.worlds.open_folder".localized())
                        Button {
                            post(.worldsImport)
                        } label: {
                            Label("server.worlds.import".localized(), systemImage: "tray.and.arrow.down")
                        }
                        .help("server.worlds.import".localized())
                        Button {
                            post(.worldsRemove)
                        } label: {
                            Label("common.remove".localized(), systemImage: "trash")
                        }
                        .help("common.remove".localized())
                        .disabled(toolbarSelection.selectedWorldId(for: server.id) == nil)
                    case "mods":
                        Button {
                            post(.modsImport)
                        } label: {
                            Label("server.mods.import".localized(), systemImage: "tray.and.arrow.down")
                        }
                        .help("server.mods.import".localized())
                        Button {
                            post(.modsRemove)
                        } label: {
                            Label("common.remove".localized(), systemImage: "trash")
                        }
                        .help("common.remove".localized())
                        .disabled(toolbarSelection.selectedModId(for: server.id) == nil)
                    case "plugins":
                        Button {
                            post(.pluginsImport)
                        } label: {
                            Label("server.plugins.import".localized(), systemImage: "tray.and.arrow.down")
                        }
                        .help("server.plugins.import".localized())
                        Button {
                            post(.pluginsRemove)
                        } label: {
                            Label("common.remove".localized(), systemImage: "trash")
                        }
                        .help("common.remove".localized())
                        .disabled(toolbarSelection.selectedPluginId(for: server.id) == nil)
                    case "players":
                        Button {
                            post(.playersAdd)
                        } label: {
                            Label("common.add".localized(), systemImage: "person.badge.plus")
                        }
                        .help("common.add".localized())
                        .disabled(toolbarSelection.selectedPlayerGroup(for: server.id) == nil)
                        Button {
                            post(.playersRemove)
                        } label: {
                            Label("common.remove".localized(), systemImage: "trash")
                        }
                        .help("common.remove".localized())
                        .disabled(toolbarSelection.selectedPlayerId(for: server.id) == nil)
                    case "console":
                        Button {
                            post(.consoleClear)
                        } label: {
                            Label("common.clear".localized(), systemImage: "trash")
                        }
                        .help("common.clear".localized())
                    case "schedules":
                        Button {
                            post(.schedulesNew)
                        } label: {
                            Label("server.schedules.add".localized(), systemImage: "note.text.badge.plus")
                        }
                        .help("server.schedules.add".localized())
                        Button {
                            post(.schedulesRunNow)
                        } label: {
                            Label("server.schedules.run_now".localized(), systemImage: "play")
                        }
                        .help("server.schedules.run_now".localized())
                        .disabled(toolbarSelection.selectedScheduleId(for: server.id) == nil)
                        Button {
                            post(.schedulesToggleEnabled)
                        } label: {
                            Label(
                                "server.schedules.enabled".localized(),
                                systemImage: toolbarSelection.isSelectedScheduleEnabled(for: server.id)
                                    ? "checkmark.circle"
                                    : "circle"
                            )
                        }
                        .help("server.schedules.enabled".localized())
                        .disabled(toolbarSelection.selectedScheduleId(for: server.id) == nil)
                    default:
                        EmptyView()
                    }
                }
            case .resource:
                if detailState.selectedProjectId != nil {
                    Button {
                        detailState.selectedProjectId = nil
                        filterState.selectedTab = 0
                    } label: {
                        Label("return".localized(), systemImage: "arrow.backward")
                    }
                    .help("return".localized())

                    Spacer()

                    Button {
                        openCurrentResourceInBrowser()
                    } label: {
                        Label("common.browser".localized(), systemImage: "safari")
                    }
                    .help("resource.open_in_browser".localized())
                } else {
                    EmptyView()
                }
            case .game:
                EmptyView()
            case .node:
                EmptyView()
            @unknown default:
                EmptyView()
            }
        }
    }
}
