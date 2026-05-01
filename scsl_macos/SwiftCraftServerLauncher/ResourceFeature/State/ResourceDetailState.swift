import SwiftUI

/// 资源/游戏详情与导航相关状态（可观测）
public final class ResourceDetailState: ObservableObject {

    @Published public var selectedItem: SidebarItem {
        didSet {
            if case .server(let id) = selectedItem {
                if serverId != id {
                    serverId = id
                }
                if let storedSection = serverPanelSectionById[id] {
                    if serverPanelSection != storedSection {
                        serverPanelSection = storedSection
                    }
                } else if serverPanelSection != "console" {
                    serverPanelSection = "console"
                }
            }
        }
    }
    @Published public var gameType: Bool  // false = local, true = server
    @Published public var gameId: String?
    @Published public var serverId: String? {
        didSet {
            if let id = serverId, id != oldValue {
                if let storedSection = serverPanelSectionById[id] {
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
            }
        }
    }
    @Published public var showServerRuntimeSettingsSheet = false
    @Published public var loadedProjectDetail: ModrinthProjectDetail?
    private var serverPanelSectionById: [String: String] = [:]

    public init(
        selectedItem: SidebarItem = .resource(.mod),
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
    }

    // MARK: - Bindings（供子视图与 GameActionManager 等使用）

    public var selectedItemBinding: Binding<SidebarItem> {
        Binding(get: { [weak self] in self?.selectedItem ?? .resource(.mod) }, set: { [weak self] value in
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
}
