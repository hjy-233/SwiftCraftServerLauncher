import SwiftUI

public struct WorkspaceTab: Codable, Identifiable, Hashable {
    public enum Kind: String, Codable {
        case server
        case resource
    }

    public let id: String
    public let kind: Kind
    public let serverId: String?
    public let section: String?
    public let resourceType: ResourceType?
    public let selectedProjectId: String?

    public init(
        id: String = UUID().uuidString,
        serverId: String,
        section: String
    ) {
        self.id = id
        kind = .server
        self.serverId = serverId
        self.section = section
        resourceType = nil
        selectedProjectId = nil
    }

    public init(
        id: String = UUID().uuidString,
        resourceType: ResourceType,
        selectedProjectId: String? = nil
    ) {
        self.id = id
        kind = .resource
        serverId = nil
        section = nil
        self.resourceType = resourceType
        self.selectedProjectId = selectedProjectId
    }

    public var matchesLogicalContentOfActiveSelection: Bool {
        switch kind {
        case .server:
            return serverId != nil && section != nil
        case .resource:
            return resourceType != nil
        }
    }
}

/// 资源/游戏详情与导航相关状态（可观测）
public final class ResourceDetailState: ObservableObject {
    private struct PersistedWorkspaceSelection: Codable {
        let kind: String
        let serverId: String?
        let serverSection: String?
        let resourceType: String?
    }

    private struct LegacyServerWorkspaceTab: Codable {
        let id: String
        let serverId: String
        let section: String
    }

    @Published public var selectedItem: SidebarItem {
        didSet {
            if case .server(let id) = selectedItem {
                if serverId != id {
                    serverId = id
                }
                if let activeWorkspaceTab,
                   activeWorkspaceTab.serverId == id,
                   let activeSection = activeWorkspaceTab.section {
                    if serverPanelSection != activeSection {
                        serverPanelSection = activeSection
                    }
                } else if let storedSection = serverPanelSectionById[id] {
                    if serverPanelSection != storedSection {
                        serverPanelSection = storedSection
                    }
                } else if serverPanelSection != "console" {
                    serverPanelSection = "console"
                }
            }
            persistSelectedWorkspaceSelection()
        }
    }
    @Published public var gameType: Bool
    @Published public var gameId: String?
    @Published public var serverId: String? {
        didSet {
            if let id = serverId, id != oldValue {
                if let activeWorkspaceTab,
                   activeWorkspaceTab.serverId == id,
                   let activeSection = activeWorkspaceTab.section {
                    if serverPanelSection != activeSection {
                        serverPanelSection = activeSection
                    }
                } else if let storedSection = serverPanelSectionById[id] {
                    if serverPanelSection != storedSection {
                        serverPanelSection = storedSection
                    }
                } else if serverPanelSection != "console" {
                    serverPanelSection = "console"
                }
            }
        }
    }
    @Published public var gameResourcesType: String
    @Published public var serverPanelSection: String = "console" {
        didSet {
            guard serverPanelSection != oldValue else { return }
            if case .server(let id) = selectedItem {
                serverPanelSectionById[id] = serverPanelSection
            }
        }
    }
    @Published public var selectedProjectId: String? {
        didSet {
            if selectedProjectId != oldValue {
                loadedProjectDetail = nil
                if selectedProjectId == nil {
                    selectedProjectSummary = nil
                }
                syncActiveResourceTabSelectedProjectId()
            }
        }
    }
    @Published public var showServerRuntimeSettingsSheet = false
    @Published public var loadedProjectDetail: ModrinthProjectDetail?
    @Published public var selectedProjectSummary: ModrinthProject?
    @Published public var workspaceTabs: [WorkspaceTab] = [] {
        didSet { persistWorkspaceTabs() }
    }
    @Published public var activeWorkspaceTabId: String? {
        didSet { persistActiveWorkspaceTabId() }
    }
    @Published public var secondaryWorkspaceTabId: String? {
        didSet { persistSecondaryWorkspaceTabId() }
    }

    private var serverPanelSectionById: [String: String] = [:]

    public init(
        selectedItem: SidebarItem = .resource(.browse),
        gameType: Bool = true,
        gameId: String? = nil,
        serverId: String? = nil,
        gameResourcesType: String = "mod",
        selectedProjectId: String? = nil,
        loadedProjectDetail: ModrinthProjectDetail? = nil
    ) {
        self.selectedItem = selectedItem
        self.gameType = gameType
        self.gameId = gameId
        self.serverId = serverId
        self.gameResourcesType = gameResourcesType
        self.serverPanelSection = "console"
        self.selectedProjectId = selectedProjectId
        self.loadedProjectDetail = loadedProjectDetail
        self.workspaceTabs = Self.loadWorkspaceTabs()
        self.activeWorkspaceTabId = Self.loadActiveWorkspaceTabId(from: workspaceTabs)
        self.secondaryWorkspaceTabId = Self.loadSecondaryWorkspaceTabId(from: workspaceTabs)
        restoreWorkspaceSelection(Self.loadSelectedWorkspaceSelection())
    }

    // MARK: - 便捷方法

    public func selectGame(id: String?) {
        gameId = id
    }

    public func selectServer(id: String?) {
        serverId = id
    }

    public func selectResource(type: String) {
        gameResourcesType = type
    }

    /// 清空项目/游戏选中状态（用于切换回列表等）
    public func clearSelection() {
        selectedProjectId = nil
        loadedProjectDetail = nil
        selectedProjectSummary = nil
    }

    public var activeWorkspaceTab: WorkspaceTab? {
        guard let activeWorkspaceTabId else {
            return nil
        }
        return workspaceTabs.first { $0.id == activeWorkspaceTabId }
    }

    public var secondaryWorkspaceTab: WorkspaceTab? {
        guard let secondaryWorkspaceTabId else {
            return nil
        }
        return workspaceTabs.first { $0.id == secondaryWorkspaceTabId }
    }

    public func openServerWorkspaceTab(
        serverId: String,
        section: String,
        forceNew: Bool = false
    ) {
        if !forceNew,
           let existingTab = workspaceTabs.first(where: {
               $0.kind == .server && $0.serverId == serverId && $0.section == section
           }) {
            activateWorkspaceTab(existingTab.id)
            return
        }

        let tab = WorkspaceTab(serverId: serverId, section: section)
        workspaceTabs.append(tab)
        activateWorkspaceTab(tab.id)
    }

    public func openResourceWorkspaceTab(
        _ type: ResourceType,
        forceNew: Bool = false,
        selectedProjectId: String? = nil
    ) {
        guard type == .browse || type == .bookmarks else {
            return
        }

        if !forceNew,
           let existingTab = workspaceTabs.first(where: {
               $0.kind == .resource && $0.resourceType == type
           }) {
            activateWorkspaceTab(existingTab.id)
            return
        }

        let tab = WorkspaceTab(
            resourceType: type,
            selectedProjectId: selectedProjectId
        )
        workspaceTabs.append(tab)
        activateWorkspaceTab(tab.id)
    }

    public func activateWorkspaceTab(_ id: String) {
        guard let tab = workspaceTabs.first(where: { $0.id == id }) else {
            return
        }

        Logger.shared.debug("工作区切换标签: \(id)")
        activeWorkspaceTabId = id

        switch tab.kind {
        case .server:
            guard let serverId = tab.serverId else {
                return
            }
            let section = tab.section ?? ServerDetailSection.console.rawValue
            serverPanelSection = section
            self.serverId = serverId
            selectedItem = .server(serverId)
        case .resource:
            let type = tab.resourceType ?? .browse
            selectedProjectSummary = nil
            selectedProjectId = tab.selectedProjectId
            selectedItem = .resource(type)
        }
    }

    public func closeWorkspaceTab(_ id: String) {
        guard let index = workspaceTabs.firstIndex(where: { $0.id == id }) else {
            return
        }

        Logger.shared.debug("工作区关闭标签: \(id)")
        let wasActive = activeWorkspaceTabId == id
        let wasSecondary = secondaryWorkspaceTabId == id
        workspaceTabs.remove(at: index)

        if wasSecondary {
            secondaryWorkspaceTabId = nil
        }
        if wasActive {
            let fallbackIndex = min(index, workspaceTabs.count - 1)
            if workspaceTabs.indices.contains(fallbackIndex) {
                activateWorkspaceTab(workspaceTabs[fallbackIndex].id)
            } else {
                activeWorkspaceTabId = nil
                secondaryWorkspaceTabId = nil
            }
        }
    }

    public func setSecondaryWorkspaceTab(_ id: String?) {
        guard let id else {
            secondaryWorkspaceTabId = nil
            return
        }
        guard workspaceTabs.contains(where: { $0.id == id }) else {
            return
        }
        secondaryWorkspaceTabId = id == activeWorkspaceTabId ? nil : id
    }

    private static let workspaceTabsKey = "workspace.tabs"
    private static let activeWorkspaceTabKey = "workspace.active_tab"
    private static let secondaryWorkspaceTabKey = "workspace.secondary_tab"
    private static let selectedWorkspaceItemKey = "workspace.selected_item"
    private static let legacyServerWorkspaceTabsKey = "workspace.server.tabs"
    private static let legacyActiveServerWorkspaceTabKey = "workspace.server.active_tab"
    private static let legacySecondaryServerWorkspaceTabKey = "workspace.server.secondary_tab"
    private static let legacyResourceWorkspaceTabsKey = "workspace.resource.tabs"
    private static let legacyActiveResourceWorkspaceTypeKey = "workspace.resource.active_type"

    private static func loadWorkspaceTabs() -> [WorkspaceTab] {
        if let data = UserDefaults.standard.data(forKey: workspaceTabsKey),
           let tabs = try? JSONDecoder().decode([WorkspaceTab].self, from: data) {
            return sanitizeWorkspaceTabs(tabs)
        }

        var migratedTabs: [WorkspaceTab] = []

        if let data = UserDefaults.standard.data(forKey: legacyServerWorkspaceTabsKey),
           let tabs = try? JSONDecoder().decode([LegacyServerWorkspaceTab].self, from: data) {
            for tab in tabs {
                let migratedTab = WorkspaceTab(
                    id: tab.id,
                    serverId: tab.serverId,
                    section: tab.section
                )
                if !migratedTabs.contains(migratedTab) {
                    migratedTabs.append(migratedTab)
                }
            }
        }

        if let data = UserDefaults.standard.data(forKey: legacyResourceWorkspaceTabsKey),
           let resourceTabs = try? JSONDecoder().decode([ResourceType].self, from: data) {
            for type in resourceTabs where type == .browse || type == .bookmarks {
                let migratedTab = WorkspaceTab(resourceType: type)
                if !migratedTabs.contains(migratedTab) {
                    migratedTabs.append(migratedTab)
                }
            }
        }

        return migratedTabs
    }

    private static func loadActiveWorkspaceTabId(from tabs: [WorkspaceTab]) -> String? {
        if let id = UserDefaults.standard.string(forKey: activeWorkspaceTabKey),
           tabs.contains(where: { $0.id == id }) {
            return id
        }

        if let legacyId = UserDefaults.standard.string(forKey: legacyActiveServerWorkspaceTabKey),
           tabs.contains(where: { $0.id == legacyId }) {
            return legacyId
        }

        if let rawType = UserDefaults.standard.string(forKey: legacyActiveResourceWorkspaceTypeKey),
           let type = ResourceType(rawValue: rawType),
           let resourceTab = tabs.first(where: { $0.resourceType == type }) {
            return resourceTab.id
        }

        return nil
    }

    private static func loadSecondaryWorkspaceTabId(from tabs: [WorkspaceTab]) -> String? {
        if let id = UserDefaults.standard.string(forKey: secondaryWorkspaceTabKey),
           tabs.contains(where: { $0.id == id }) {
            return id
        }

        if let legacyId = UserDefaults.standard.string(forKey: legacySecondaryServerWorkspaceTabKey),
           tabs.contains(where: { $0.id == legacyId }) {
            return legacyId
        }

        return nil
    }

    private static func loadSelectedWorkspaceSelection() -> PersistedWorkspaceSelection? {
        guard let data = UserDefaults.standard.data(forKey: selectedWorkspaceItemKey),
              let selection = try? JSONDecoder().decode(PersistedWorkspaceSelection.self, from: data) else {
            return nil
        }
        return selection
    }

    private static func sanitizeWorkspaceTabs(_ tabs: [WorkspaceTab]) -> [WorkspaceTab] {
        var sanitizedTabs: [WorkspaceTab] = []

        for tab in tabs {
            switch tab.kind {
            case .server:
                guard let serverId = tab.serverId else {
                    continue
                }
                let section = tab.section ?? ServerDetailSection.console.rawValue
                let normalizedTab = WorkspaceTab(id: tab.id, serverId: serverId, section: section)
                if !sanitizedTabs.contains(normalizedTab) {
                    sanitizedTabs.append(normalizedTab)
                }
            case .resource:
                guard let resourceType = tab.resourceType,
                      resourceType == .browse || resourceType == .bookmarks else {
                    continue
                }
                let normalizedTab = WorkspaceTab(
                    id: tab.id,
                    resourceType: resourceType,
                    selectedProjectId: tab.selectedProjectId
                )
                if !sanitizedTabs.contains(normalizedTab) {
                    sanitizedTabs.append(normalizedTab)
                }
            }
        }

        return sanitizedTabs
    }

    private func persistWorkspaceTabs() {
        guard let data = try? JSONEncoder().encode(workspaceTabs) else {
            return
        }
        UserDefaults.standard.set(data, forKey: Self.workspaceTabsKey)
    }

    private func persistActiveWorkspaceTabId() {
        UserDefaults.standard.set(activeWorkspaceTabId, forKey: Self.activeWorkspaceTabKey)
    }

    private func persistSecondaryWorkspaceTabId() {
        UserDefaults.standard.set(secondaryWorkspaceTabId, forKey: Self.secondaryWorkspaceTabKey)
    }

    private func persistSelectedWorkspaceSelection() {
        let selection: PersistedWorkspaceSelection

        switch selectedItem {
        case .server(let serverId):
            selection = PersistedWorkspaceSelection(
                kind: "server",
                serverId: serverId,
                serverSection: serverPanelSection,
                resourceType: nil
            )
        case .resource(let type):
            selection = PersistedWorkspaceSelection(
                kind: "resource",
                serverId: nil,
                serverSection: nil,
                resourceType: type.rawValue
            )
        default:
            return
        }

        guard let data = try? JSONEncoder().encode(selection) else {
            return
        }
        UserDefaults.standard.set(data, forKey: Self.selectedWorkspaceItemKey)
    }

    private func restoreWorkspaceSelection(_ selection: PersistedWorkspaceSelection?) {
        if let activeWorkspaceTabId,
           !workspaceTabs.contains(where: { $0.id == activeWorkspaceTabId }) {
            self.activeWorkspaceTabId = nil
        }

        if let secondaryWorkspaceTabId,
           !workspaceTabs.contains(where: { $0.id == secondaryWorkspaceTabId }) {
            self.secondaryWorkspaceTabId = nil
        }

        if secondaryWorkspaceTabId == activeWorkspaceTabId {
            secondaryWorkspaceTabId = nil
        }

        if let selection {
            switch selection.kind {
            case "server":
                if let selectedServerId = selection.serverId {
                    let restoredTab =
                        workspaceTabs.first {
                            $0.serverId == selectedServerId && $0.section == selection.serverSection
                        } ?? workspaceTabs.first { $0.serverId == selectedServerId }
                    if let restoredTab {
                        activeWorkspaceTabId = restoredTab.id
                        self.serverId = restoredTab.serverId
                        serverPanelSection = restoredTab.section ?? ServerDetailSection.console.rawValue
                        if let restoredServerId = restoredTab.serverId {
                            selectedItem = .server(restoredServerId)
                        }
                        return
                    }
                }
            case "resource":
                if let resourceType = selection.resourceType.flatMap(ResourceType.init(rawValue:)),
                   let restoredTab = workspaceTabs.first(where: { $0.resourceType == resourceType }) {
                    activeWorkspaceTabId = restoredTab.id
                    selectedProjectId = restoredTab.selectedProjectId
                    selectedItem = .resource(resourceType)
                    return
                }
            default:
                break
            }
        }

        if let activeWorkspaceTabId,
           let activeTab = workspaceTabs.first(where: { $0.id == activeWorkspaceTabId }) {
            switch activeTab.kind {
            case .server:
                if let activeServerId = activeTab.serverId {
                    serverId = activeServerId
                    serverPanelSection = activeTab.section ?? ServerDetailSection.console.rawValue
                    selectedItem = .server(activeServerId)
                }
            case .resource:
                selectedProjectId = activeTab.selectedProjectId
                selectedItem = .resource(activeTab.resourceType ?? .browse)
            }
            return
        }

        if let firstTab = workspaceTabs.first {
            activeWorkspaceTabId = firstTab.id
            switch firstTab.kind {
            case .server:
                if let firstServerId = firstTab.serverId {
                    serverId = firstServerId
                    serverPanelSection = firstTab.section ?? ServerDetailSection.console.rawValue
                    selectedItem = .server(firstServerId)
                }
            case .resource:
                selectedProjectId = firstTab.selectedProjectId
                selectedItem = .resource(firstTab.resourceType ?? .browse)
            }
        }
    }

    private func syncActiveResourceTabSelectedProjectId() {
        guard case .resource = selectedItem,
              let activeWorkspaceTabId,
              let index = workspaceTabs.firstIndex(where: { $0.id == activeWorkspaceTabId }),
              workspaceTabs[index].kind == .resource,
              let resourceType = workspaceTabs[index].resourceType else {
            return
        }

        let currentTab = workspaceTabs[index]
        if currentTab.selectedProjectId == selectedProjectId {
            return
        }

        workspaceTabs[index] = WorkspaceTab(
            id: currentTab.id,
            resourceType: resourceType,
            selectedProjectId: selectedProjectId
        )
    }

    // MARK: - Bindings（供子视图与 GameActionManager 等使用）

    public var selectedItemBinding: Binding<SidebarItem> {
        Binding(get: { [weak self] in self?.selectedItem ?? .resource(.browse) }, set: { [weak self] value in
            guard let self else { return }
            DispatchQueue.main.async { self.selectedItem = value }
        })
    }

    /// 用于 List(selection:) 等需要 Optional 的 API
    public var selectedItemOptionalBinding: Binding<SidebarItem?> {
        Binding(get: { [weak self] in self?.selectedItem }, set: { [weak self] value in
            guard let self else { return }
            DispatchQueue.main.async { if let v = value { self.selectedItem = v } }
        })
    }
    public var gameTypeBinding: Binding<Bool> {
        Binding(get: { [weak self] in self?.gameType ?? true }, set: { [weak self] value in
            guard let self else { return }
            DispatchQueue.main.async { self.gameType = value }
        })
    }
    public var gameIdBinding: Binding<String?> {
        Binding(get: { [weak self] in self?.gameId }, set: { [weak self] value in
            guard let self else { return }
            DispatchQueue.main.async { self.gameId = value }
        })
    }
    public var serverIdBinding: Binding<String?> {
        Binding(get: { [weak self] in self?.serverId }, set: { [weak self] value in
            guard let self else { return }
            DispatchQueue.main.async { self.serverId = value }
        })
    }
    public var gameResourcesTypeBinding: Binding<String> {
        Binding(get: { [weak self] in self?.gameResourcesType ?? "mod" }, set: { [weak self] value in
            guard let self else { return }
            DispatchQueue.main.async { self.gameResourcesType = value }
        })
    }
    public var selectedProjectIdBinding: Binding<String?> {
        Binding(get: { [weak self] in self?.selectedProjectId }, set: { [weak self] value in
            guard let self else { return }
            DispatchQueue.main.async { self.selectedProjectId = value }
        })
    }
    public var loadedProjectDetailBinding: Binding<ModrinthProjectDetail?> {
        Binding(get: { [weak self] in self?.loadedProjectDetail }, set: { [weak self] value in
            guard let self else { return }
            DispatchQueue.main.async { self.loadedProjectDetail = value }
        })
    }
    public var selectedProjectSummaryBinding: Binding<ModrinthProject?> {
        Binding(get: { [weak self] in self?.selectedProjectSummary }, set: { [weak self] value in
            guard let self else { return }
            DispatchQueue.main.async { self.selectedProjectSummary = value }
        })
    }
}
