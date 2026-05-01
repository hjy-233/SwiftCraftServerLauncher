import SwiftUI
import AppKit

struct DetailView: View {
    @EnvironmentObject var filterState: ResourceFilterState
    @EnvironmentObject var detailState: ResourceDetailState
    @EnvironmentObject var serverRepository: ServerRepository
    @EnvironmentObject var serverNodeRepository: ServerNodeRepository
    @State private var requestOpenLaunchCommandEditor = false

    private var currentServer: ServerInstance? {
        if case .server(let serverId) = detailState.selectedItem {
            return serverRepository.getServer(by: serverId)
        }
        return nil
    }

    var body: some View {
        Group {
            switch detailState.selectedItem {
            case .game:
                Text("game.module.removed".localized())
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .server(let serverId):
                serverDetailView(serverId: serverId).frame(maxWidth: .infinity, alignment: .leading)
            case .node:
                EmptyView()
            case .resource(let type):
                resourceDetailView(type: type)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $detailState.showServerRuntimeSettingsSheet) {
            if let server = currentServer {
                CommonSheetView {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("server.launch.title".localized())
                                .font(.headline)
                            Text("server.runtime.page.subtitle".localized())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            requestOpenLaunchCommandEditor = true
                        } label: {
                            Label("\("server.launch.title".localized())…", systemImage: "ellipsis.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } body: {
                    ServerRuntimeSettingsView(
                        server: server,
                        showPageHeader: false,
                        externalAdvancedEditorRequest: $requestOpenLaunchCommandEditor
                    )
                        .frame(width: 760, height: 520)
                } footer: {
                    HStack {
                        Spacer()
                        Button("common.close".localized()) {
                            detailState.showServerRuntimeSettingsSheet = false
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func resourceDetailView(type: ResourceType) -> some View {
        ZStack {
            if detailState.selectedProjectId != nil {
                List {
                    ModrinthProjectDetailView(
                        projectDetail: detailState.loadedProjectDetail
                    )
                }
                .transition(.resourcePanelForward)
            } else {
                ModrinthDetailView(
                    query: type.rawValue,
                    selectedVersions: filterState.selectedVersionsBinding,
                    selectedCategories: filterState.selectedCategoriesBinding,
                    selectedFeatures: filterState.selectedFeaturesBinding,
                    selectedResolutions: filterState.selectedResolutionsBinding,
                    selectedPerformanceImpact: filterState.selectedPerformanceImpactBinding,
                    selectedProjectId: detailState.selectedProjectIdBinding,
                    selectedLoader: filterState.selectedLoadersBinding,
                    gameInfo: nil,
                    selectedItem: detailState.selectedItemBinding,
                    gameType: detailState.gameTypeBinding,
                    dataSource: filterState.dataSourceBinding,
                    searchText: filterState.searchTextBinding
                )
                .transition(.resourcePanelBackward)
            }
        }
        .clipped()
        .animation(.easeInOut(duration: 0.28), value: detailState.selectedProjectId)
    }

    @ViewBuilder
    private func serverDetailView(serverId: String) -> some View {
        if let server = serverRepository.getServer(by: serverId) {
            ZStack {
                switch detailState.serverPanelSection {
                case "serverConfig":
                    ServerPropertiesEditorView(server: server)
                case "players":
                    ServerPlayersView(server: server)
                case "worlds":
                    ServerWorldsManagerView(server: server)
                case "mods":
                    if server.serverType == .fabric || server.serverType == .forge {
                        ServerModsManagerView(server: server)
                    } else {
                        ServerConsoleView(server: server)
                    }
                case "plugins":
                    if server.serverType == .paper {
                        ServerPluginsManagerView(server: server)
                    } else {
                        ServerConsoleView(server: server)
                    }
                case "schedules":
                    ServerSchedulesView(server: server)
                case "logs":
                    ServerLogManagerView(server: server)
                default:
                    ServerConsoleView(server: server)
                }
            }
            .id("\(server.id)-\(detailState.serverPanelSection)")
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            .animation(.easeInOut(duration: 0.18), value: detailState.serverPanelSection)
        }
    }
}
