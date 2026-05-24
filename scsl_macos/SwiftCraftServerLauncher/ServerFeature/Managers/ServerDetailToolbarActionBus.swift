import Foundation

enum ServerDetailToolbarAction: String {
    case consoleClear
    case worldsOpenFolder
    case worldsImport
    case worldsRemove
    case modsImport
    case modsRemove
    case pluginsImport
    case pluginsRemove
    case configToggleSidebar
    case configUpload
    case configNewFolder
    case configNewFile
    case configRename
    case configDelete
    case playersAdd
    case playersRemove
    case schedulesNew
    case schedulesRunNow
    case schedulesToggleEnabled
}

@MainActor
final class ServerDetailToolbarSelectionState: ObservableObject {
    static let shared = ServerDetailToolbarSelectionState()

    @Published var selectedModIdByServerId: [String: String] = [:]
    @Published var selectedPluginIdByServerId: [String: String] = [:]
    @Published var selectedWorldIdByServerId: [String: String] = [:]
    @Published var selectedPlayerGroupByServerId: [String: String] = [:]
    @Published var selectedPlayerIdByServerId: [String: String] = [:]
    @Published var selectedScheduleIdByServerId: [String: ServerSchedule.ID] = [:]
    @Published var selectedScheduleEnabledByServerId: [String: Bool] = [:]

    private init() {}

    func selectedModId(for serverId: String) -> String? {
        selectedModIdByServerId[serverId]
    }

    func selectedPluginId(for serverId: String) -> String? {
        selectedPluginIdByServerId[serverId]
    }

    func selectedWorldId(for serverId: String) -> String? {
        selectedWorldIdByServerId[serverId]
    }

    func selectedPlayerGroup(for serverId: String) -> String? {
        selectedPlayerGroupByServerId[serverId]
    }

    func selectedPlayerId(for serverId: String) -> String? {
        selectedPlayerIdByServerId[serverId]
    }

    func selectedScheduleId(for serverId: String) -> ServerSchedule.ID? {
        selectedScheduleIdByServerId[serverId]
    }

    func isSelectedScheduleEnabled(for serverId: String) -> Bool {
        selectedScheduleEnabledByServerId[serverId] ?? false
    }

    func updateScheduleSelection(serverId: String, id: ServerSchedule.ID?, isEnabled: Bool = false) {
        selectedScheduleIdByServerId[serverId] = id
        selectedScheduleEnabledByServerId[serverId] = id == nil ? nil : isEnabled
    }
}

extension Notification.Name {
    static let serverDetailToolbarAction = Notification.Name("serverDetailToolbarAction")
}

enum ServerDetailToolbarActionBus {
    static func post(_ action: ServerDetailToolbarAction) {
        NotificationCenter.default.post(
            name: .serverDetailToolbarAction,
            object: nil,
            userInfo: ["action": action.rawValue]
        )
    }

    static func action(from notification: Notification) -> ServerDetailToolbarAction? {
        guard let raw = notification.userInfo?["action"] as? String else { return nil }
        return ServerDetailToolbarAction(rawValue: raw)
    }
}
