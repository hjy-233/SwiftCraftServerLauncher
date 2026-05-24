import SwiftUI
import AppKit

struct DetailView: View {
    let showsUnifiedWorkspaceHeader: Bool

    @EnvironmentObject var filterState: ResourceFilterState
    @EnvironmentObject var detailState: ResourceDetailState
    @EnvironmentObject var serverRepository: ServerRepository
    @EnvironmentObject var serverNodeRepository: ServerNodeRepository
    @State private var requestOpenLaunchCommandEditor = false
    @State private var requestedResourceDetailSection: ResourceDetailSection?
    @StateObject private var generalSettings = GeneralSettingsManager.shared

    init(showsUnifiedWorkspaceHeader: Bool = true) {
        self.showsUnifiedWorkspaceHeader = showsUnifiedWorkspaceHeader
    }

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
                serverDetailContainer(serverId: serverId)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .node:
                EmptyView()
            case .resource(let type):
                resourceDetailContainer(type: type)
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
    private func serverDetailContainer(serverId: String) -> some View {
        if let server = serverRepository.getServer(by: serverId) {
            if generalSettings.serverInterfaceMode == .workspace {
                unifiedWorkspaceContainer(for: .server(serverId))
            } else {
                workspaceContainer {
                    ServerDetailNavigationBar(server: server)
                } content: {
                    serverDetailView(server: server, section: detailState.serverPanelSection)
                }
            }
        }
    }

    @ViewBuilder
    private func resourceDetailContainer(type: ResourceType) -> some View {
        if generalSettings.serverInterfaceMode == .workspace,
           type == .browse || type == .bookmarks {
            unifiedWorkspaceContainer(for: .resource(type))
        } else {
            resourceDetailView(type: type)
        }
    }

    @ViewBuilder
    private func unifiedWorkspaceContainer(for selection: SidebarItem) -> some View {
        Group {
            if showsUnifiedWorkspaceHeader {
                workspaceContainer {
                    UnifiedWorkspaceNavigationBar()
                } content: {
                    unifiedWorkspaceBody(for: selection)
                }
            } else {
                unifiedWorkspaceBody(for: selection)
            }
        }
        .onAppear {
            ensureWorkspaceTabIfNeeded(for: selection)
        }
        .onChange(of: selection.id) { _, _ in
            ensureWorkspaceTabIfNeeded(for: selection)
        }
    }

    @ViewBuilder
    private func unifiedWorkspaceBody(for selection: SidebarItem) -> some View {
        if let activeTab = detailState.activeWorkspaceTab {
            workspaceContentView(primaryTab: activeTab)
        } else {
            fallbackWorkspaceContent(for: selection)
        }
    }

    @ViewBuilder
    private func workspaceContentView(primaryTab: WorkspaceTab) -> some View {
        if let secondaryTab = detailState.secondaryWorkspaceTab {
            HSplitView {
                workspaceTabView(primaryTab)
                workspaceTabView(secondaryTab)
            }
        } else {
            workspaceTabView(primaryTab)
        }
    }

    @ViewBuilder
    private func workspaceTabView(_ tab: WorkspaceTab) -> some View {
        switch tab.kind {
        case .server:
            if let serverId = tab.serverId,
               let server = serverRepository.getServer(by: serverId) {
                serverDetailView(
                    server: server,
                    section: tab.section ?? ServerDetailSection.console.rawValue
                )
            } else {
                Text("game.module.removed".localized())
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        case .resource:
            resourceDetailView(type: tab.resourceType ?? .browse)
        }
    }

    @ViewBuilder
    private func fallbackWorkspaceContent(for selection: SidebarItem) -> some View {
        switch selection {
        case .server(let serverId):
            if let server = serverRepository.getServer(by: serverId) {
                serverDetailView(server: server, section: detailState.serverPanelSection)
            }
        case .resource(let type):
            resourceDetailView(type: type)
        default:
            EmptyView()
        }
    }

    private func ensureWorkspaceTabIfNeeded(for selection: SidebarItem) {
        switch selection {
        case .server(let serverId):
            if let activeTab = detailState.activeWorkspaceTab,
               activeTab.kind == .server,
               activeTab.serverId == serverId,
               activeTab.section == detailState.serverPanelSection {
                return
            }
            detailState.openServerWorkspaceTab(
                serverId: serverId,
                section: detailState.serverPanelSection
            )
        case .resource(let type):
            if let activeTab = detailState.activeWorkspaceTab,
               activeTab.kind == .resource,
               activeTab.resourceType == type {
                return
            }
            detailState.openResourceWorkspaceTab(type)
        default:
            break
        }
    }

    private func workspaceContainer<Header: View, Content: View>(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            header()
            Divider()
            content()
        }
    }

    @ViewBuilder
    private func resourceDetailView(type: ResourceType) -> some View {
        ZStack {
            if let projectId = detailState.selectedProjectId {
                GeometryReader { proxy in
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            ModrinthProjectDetailView(
                                projectDetail: detailState.loadedProjectDetail,
                                projectSummary: detailState.selectedProjectSummary,
                                selectedItem: detailState.selectedItemBinding
                            ) { section in
                                requestedResourceDetailSection = section
                            }
                            .frame(
                                maxWidth: .infinity,
                                minHeight: proxy.size.height,
                                alignment: .topLeading
                            )
                        }
                        .contentMargins(0, for: .scrollContent)
                        .scrollContentBackground(.hidden)
                        .onChange(of: requestedResourceDetailSection) { _, section in
                            guard let section else { return }
                            withAnimation(.easeInOut(duration: 0.25)) {
                                scrollProxy.scrollTo(section, anchor: .top)
                            }
                            requestedResourceDetailSection = nil
                        }
                    }
                }
                .task(id: projectId) {
                    await loadSelectedProjectDetail(projectId: projectId)
                }
                .transition(.resourcePanelForward)
            } else if type == .bookmarks {
                ResourceBookmarksView(
                    selectedProjectId: detailState.selectedProjectIdBinding,
                    selectedProjectSummary: detailState.selectedProjectSummaryBinding,
                    selectedItem: detailState.selectedItemBinding
                )
                .transition(.resourcePanelBackward)
            } else {
                ModrinthDetailView(
                    resourceType: type,
                    projectTypes: projectTypes(for: type),
                    selectedVersions: filterState.selectedVersionsBinding,
                    selectedCategories: filterState.selectedCategoriesBinding,
                    selectedFeatures: filterState.selectedFeaturesBinding,
                    selectedResolutions: filterState.selectedResolutionsBinding,
                    selectedPerformanceImpact: filterState.selectedPerformanceImpactBinding,
                    selectedProjectId: detailState.selectedProjectIdBinding,
                    selectedProjectSummary: detailState.selectedProjectSummaryBinding,
                    selectedLoader: filterState.selectedLoadersBinding,
                    gameInfo: nil,
                    selectedItem: detailState.selectedItemBinding,
                    gameType: detailState.gameTypeBinding,
                    dataSource: filterState.dataSourceBinding,
                    searchText: filterState.searchTextBinding
                )
                .id("\(type.rawValue)-\(filterState.resourceBrowseScope.rawValue)")
                .transition(.resourcePanelBackward)
            }
        }
        .clipped()
        .animation(.easeInOut(duration: 0.28), value: detailState.selectedProjectId)
    }

    private func loadSelectedProjectDetail(projectId: String) async {
        guard !projectId.isEmpty else {
            GlobalErrorHandler.shared.handle(GlobalError.validation(
                chineseMessage: "项目ID不能为空",
                i18nKey: "error.validation.project_id_empty",
                level: .notification
            ))
            return
        }

        if detailState.loadedProjectDetail?.id == projectId {
            return
        }

        guard let fetchedProject = await ModrinthService.fetchProjectDetails(id: projectId) else {
            GlobalErrorHandler.shared.handle(GlobalError.resource(
                chineseMessage: "无法获取项目详情",
                i18nKey: "error.resource.project_details_not_found",
                level: .notification
            ))
            return
        }

        await MainActor.run {
            if detailState.selectedProjectId == projectId {
                detailState.loadedProjectDetail = fetchedProject
            }
        }
    }

    private func projectTypes(for type: ResourceType) -> [String] {
        switch type {
        case .browse:
            return filterState.resourceBrowseScope.projectTypes
        case .bookmarks:
            return ResourceBrowseScope.all.projectTypes
        default:
            return [type.rawValue]
        }
    }

    @ViewBuilder
    private func serverDetailView(server: ServerInstance, section: String) -> some View {
        ZStack {
            switch section {
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
        .id("\(server.id)-\(section)")
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
        .animation(.easeInOut(duration: 0.18), value: section)
    }
}

struct UnifiedWorkspaceNavigationBar: View {
    @EnvironmentObject private var detailState: ResourceDetailState
    @EnvironmentObject private var serverRepository: ServerRepository

    var body: some View {
        WorkspaceTabsStripView(
            tabs: workspaceTabItems,
            activeTabId: detailState.activeWorkspaceTabId,
            onActivate: detailState.activateWorkspaceTab,
            onClose: detailState.closeWorkspaceTab
        ) {
            EmptyView()
        } trailingContent: {
            WorkspaceSplitMenuButton()
        }
    }

    private var workspaceTabItems: [WorkspaceTabItem] {
        detailState.workspaceTabs.map { tab in
            switch tab.kind {
            case .server:
                let section = ServerDetailSection(rawValue: tab.section ?? "") ?? .console
                let serverName = tab.serverId.flatMap { serverRepository.getServer(by: $0)?.name }
                    ?? tab.serverId
                    ?? "-"
                return WorkspaceTabItem(
                    id: tab.id,
                    title: "\(serverName) · \(section.title)",
                    systemImage: section.systemImage,
                    minWidth: 150,
                    maxWidth: 220
                )
            case .resource:
                let resourceType = tab.resourceType ?? .browse
                return WorkspaceTabItem(
                    id: tab.id,
                    title: resourceType.localizedName,
                    systemImage: resourceType.systemImage,
                    minWidth: 130,
                    maxWidth: 180
                )
            }
        }
    }
}

private struct WorkspaceSplitMenuButton: View {
    @EnvironmentObject private var detailState: ResourceDetailState
    @EnvironmentObject private var serverRepository: ServerRepository

    var body: some View {
        HStack(spacing: 0) {
            Menu {
                Button("server.workspace.close_split".localized()) {
                    detailState.setSecondaryWorkspaceTab(nil)
                }
                .disabled(detailState.secondaryWorkspaceTabId == nil)

                Divider()

                ForEach(splitCandidateTabs) { tab in
                    Button {
                        detailState.setSecondaryWorkspaceTab(tab.id)
                    } label: {
                        Label(tabTitle(tab), systemImage: tabSystemImage(tab))
                    }
                }
            } label: {
                Image(systemName: "rectangle.split.2x1")
                    .frame(width: 28, height: 24)
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
            .help("server.workspace.split_view".localized())
        }
    }

    private var splitCandidateTabs: [WorkspaceTab] {
        detailState.workspaceTabs.filter { $0.id != detailState.activeWorkspaceTabId }
    }

    private func tabTitle(_ tab: WorkspaceTab) -> String {
        switch tab.kind {
        case .server:
            let section = ServerDetailSection(rawValue: tab.section ?? "") ?? .console
            let serverName = tab.serverId.flatMap { serverRepository.getServer(by: $0)?.name }
                ?? tab.serverId
                ?? "-"
            return "\(serverName) · \(section.title)"
        case .resource:
            return (tab.resourceType ?? .browse).localizedName
        }
    }

    private func tabSystemImage(_ tab: WorkspaceTab) -> String {
        switch tab.kind {
        case .server:
            return (ServerDetailSection(rawValue: tab.section ?? "") ?? .console).systemImage
        case .resource:
            return (tab.resourceType ?? .browse).systemImage
        }
    }
}

private struct ResourceBookmarksView: View {
    @ObservedObject private var bookmarkStore = ResourceBookmarkStore.shared
    @EnvironmentObject private var detailState: ResourceDetailState
    @EnvironmentObject private var filterState: ResourceFilterState
    @EnvironmentObject private var generalSettings: GeneralSettingsManager
    @Binding var selectedProjectId: String?
    @Binding var selectedProjectSummary: ModrinthProject?
    @Binding var selectedItem: SidebarItem
    @State private var scannedDetailIds: Set<String> = []

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: gridSpacing, alignment: .top),
            count: 2
        )
    }

    private var gridSpacing: CGFloat {
        generalSettings.resourceCardStyle == .compact ? 14 : 18
    }

    private var filteredProjects: [ModrinthProject] {
        bookmarkStore.projects.filter(matchesBookmarkFilter)
    }

    var body: some View {
        ScrollView {
            if bookmarkStore.projects.isEmpty {
                ContentUnavailableView(
                    "resource.bookmark.empty.title".localized(),
                    systemImage: "bookmark",
                    description: Text("resource.bookmark.empty.description".localized())
                )
                .frame(maxWidth: .infinity, minHeight: 280)
                .padding(24)
            } else if filteredProjects.isEmpty {
                ContentUnavailableView(
                    "common.empty".localized(),
                    systemImage: "line.3.horizontal.decrease.circle"
                )
                .frame(maxWidth: .infinity, minHeight: 280)
                .padding(24)
            } else {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: gridSpacing) {
                    ForEach(filteredProjects, id: \.projectId) { project in
                        ModrinthDetailCardView(
                            project: project,
                            selectedVersions: filterState.selectedVersions,
                            selectedLoaders: normalizedSelectedLoaders,
                            gameInfo: nil,
                            query: project.projectType,
                            type: true,
                            selectedItem: $selectedItem,
                            scannedDetailIds: $scannedDetailIds
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            openBookmarkedProject(project)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
        }
    }

    private var normalizedSelectedLoaders: [String] {
        filterState.selectedLoaders.map {
            $0.caseInsensitiveCompare("vanilla") == .orderedSame ? "minecraft" : $0
        }
    }

    private func matchesBookmarkFilter(_ project: ModrinthProject) -> Bool {
        matchesBrowseScope(project)
            && matchesSearchText(project)
            && matchesVersions(project)
            && matchesCategories(project)
            && matchesResolutions(project)
            && matchesPerformanceImpact(project)
            && matchesLoaders(project)
            && matchesEnvironment(project)
    }

    private func matchesBrowseScope(_ project: ModrinthProject) -> Bool {
        filterState.resourceBrowseScope.projectTypes.contains(project.projectType)
    }

    private func matchesSearchText(_ project: ModrinthProject) -> Bool {
        let query = filterState.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        return [
            project.title,
            project.description,
            project.author,
            project.slug,
        ].contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func matchesVersions(_ project: ModrinthProject) -> Bool {
        let selectedVersions = filterState.selectedVersions
        guard !selectedVersions.isEmpty else { return true }
        return !Set(project.versions).isDisjoint(with: selectedVersions)
    }

    private func matchesCategories(_ project: ModrinthProject) -> Bool {
        matchesTagGroup(filterState.selectedCategories, in: project)
    }

    private func matchesResolutions(_ project: ModrinthProject) -> Bool {
        matchesTagGroup(filterState.selectedResolutions, in: project)
    }

    private func matchesPerformanceImpact(_ project: ModrinthProject) -> Bool {
        matchesTagGroup(filterState.selectedPerformanceImpact, in: project)
    }

    private func matchesLoaders(_ project: ModrinthProject) -> Bool {
        matchesTagGroup(normalizedSelectedLoaders, in: project)
    }

    private func matchesTagGroup(_ selectedTags: [String], in project: ModrinthProject) -> Bool {
        guard !selectedTags.isEmpty else { return true }

        let normalizedTags = Set((project.categories + project.displayCategories).map {
            $0.lowercased()
        })
        return selectedTags.contains { normalizedTags.contains($0.lowercased()) }
    }

    private func matchesEnvironment(_ project: ModrinthProject) -> Bool {
        let selectedFeatures = Set(filterState.selectedFeatures.map { $0.lowercased() })
        guard !selectedFeatures.isEmpty else { return true }

        let clientSide = project.clientSide.lowercased()
        let serverSide = project.serverSide.lowercased()
        let hasClient = selectedFeatures.contains(AppConstants.EnvironmentTypes.client)
        let hasServer = selectedFeatures.contains(AppConstants.EnvironmentTypes.server)

        if hasClient && clientSide != "required" {
            return false
        }
        if hasServer && serverSide != "required" {
            return false
        }
        if hasClient != hasServer {
            if hasClient && serverSide != "optional" {
                return false
            }
            if hasServer && clientSide != "optional" {
                return false
            }
        }

        return true
    }

    private func openBookmarkedProject(_ project: ModrinthProject) {
        withAnimation(.easeInOut(duration: 0.28)) {
            if generalSettings.serverInterfaceMode == .workspace,
               NSEvent.modifierFlags.contains(.command) {
                detailState.openResourceWorkspaceTab(
                    .bookmarks,
                    forceNew: true,
                    selectedProjectId: project.projectId
                )
                selectedProjectSummary = project
                return
            }

            selectedProjectSummary = project
            selectedProjectId = project.projectId
            selectedItem = .resource(.bookmarks)
        }
    }
}
