import SwiftUI

struct ContentView: View {
    @EnvironmentObject var filterState: ResourceFilterState
    @EnvironmentObject var detailState: ResourceDetailState
    @EnvironmentObject var serverRepository: ServerRepository
    @EnvironmentObject var serverNodeRepository: ServerNodeRepository

    var body: some View {
        List {
            switch detailState.selectedItem {
            case .game(let gameId):
                Text("\("game.module.removed.with_id".localized())\(gameId)")
                    .foregroundColor(.secondary)
            case .server(let serverId):
                serverContentView(serverId: serverId)
            case .node(let nodeId):
                Text("\("node.selected".localized())\(serverNodeRepository.getNode(by: nodeId)?.name ?? nodeId)")
                    .foregroundColor(.secondary)
            case .resource(let type):
                resourceContentView(type: type)
            }
        }
    }

    @ViewBuilder
    private func resourceContentView(type: ResourceType) -> some View {
        if detailState.selectedProjectId != nil {
            EmptyView()
        } else {
            CategoryContentView(
                project: filterProject(for: type),
                type: "resource",
                selectedCategories: filterState.selectedCategoriesBinding,
                selectedFeatures: filterState.selectedFeaturesBinding,
                selectedResolutions: filterState.selectedResolutionsBinding,
                selectedPerformanceImpacts: filterState.selectedPerformanceImpactBinding,
                selectedVersions: filterState.selectedVersionsBinding,
                selectedLoaders: filterState.selectedLoadersBinding,
                browseScope: filterState.resourceBrowseScopeBinding,
                showsBrowseScopePicker: type == .browse || type == .bookmarks,
                dataSource: filterState.dataSource
            )
            .id("\(type.rawValue)-\(filterState.resourceBrowseScope.rawValue)")
            .transition(.resourcePanelBackward)
        }
    }

    private func filterProject(for type: ResourceType) -> String {
        switch type {
        case .browse:
            return filterState.resourceBrowseScope.primaryProjectType
        case .bookmarks:
            return filterState.resourceBrowseScope.primaryProjectType
        default:
            return type.rawValue
        }
    }

    @ViewBuilder
    private func serverContentView(serverId: String) -> some View {
        if let server = serverRepository.getServer(by: serverId) {
            ServerLaunchCommandView(server: server)
                .environmentObject(serverRepository)
        }
    }
}
