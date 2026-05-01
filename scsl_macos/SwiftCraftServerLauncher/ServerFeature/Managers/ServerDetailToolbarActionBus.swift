import Foundation

enum ServerDetailToolbarAction: String {
    case consoleClear
    case worldsOpenFolder
    case worldsImport
    case modsImport
    case pluginsImport
    case configToggleSidebar
    case configUpload
    case configNewFolder
    case configNewFile
    case configRename
    case configDelete
    case schedulesNew
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
