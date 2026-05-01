import Foundation

/// 侧边栏导航项
public enum SidebarItem: Hashable, Identifiable {
    case game(String)  // 游戏项，包含游戏ID
    case server(String)
    case node(String)
    case resource(ResourceType)  // 资源项

    public var id: String {
        switch self {
        case .game(let gameId):
            return "game_\(gameId)"
        case .server(let serverId):
            return "server_\(serverId)"
        case .node(let nodeId):
            return "node_\(nodeId)"
        case .resource(let type):
            return "resource_\(type.rawValue)"
        }
    }

    public var title: String {
        switch self {
        case .game(let gameId):
            return gameId  // 可从游戏数据获取名称
        case .server(let serverId):
            return serverId
        case .node(let nodeId):
            return nodeId
        case .resource(let type):
            return type.localizedName
        }
    }
}

/// 资源类型
public enum ResourceType: String, CaseIterable {
    case mod = "mod"
    case plugin = "plugin"
    case datapack = "datapack"
    case shader = "shader"
    case resourcepack = "resourcepack"
    case modpack = "modpack"

    public var localizedName: String {
        return "resource.content.type.\(rawValue)".localized()
    }

    /// 资源类型的 SF Symbol 图标名称
    public var systemImage: String {
        switch self {
        case .mod:
            return "puzzlepiece.extension"
        case .plugin:
            return "powerplug"
        case .datapack:
            return "doc.on.doc"
        case .shader:
            return "sparkles"
        case .resourcepack:
            return "photo.stack"
        case .modpack:
            return "cube.box"
        }
    }
}
