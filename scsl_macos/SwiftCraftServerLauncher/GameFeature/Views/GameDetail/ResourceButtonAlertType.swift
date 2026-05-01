import SwiftUI

/// 资源按钮的 Alert 类型枚举
enum ResourceButtonAlertType: Identifiable {
    case noGame
    case noServer
    case noPlayer

    var id: Self { self }

    /// 创建对应的 Alert
    var alert: Alert {
        switch self {
        case .noGame:
            return Alert(
                title: Text("no_local_game.title".localized()),
                message: Text("no_local_game.message".localized()),
                dismissButton: .default(Text("common.confirm".localized()))
            )
        case .noPlayer:
            return Alert(
                title: Text("sidebar.alert.no_player.title".localized()),
                message: Text("sidebar.alert.no_player.message".localized()),
                dismissButton: .default(Text("common.confirm".localized()))
            )
        case .noServer:
            return Alert(
                title: Text("No Server"),
                message: Text("Create a compatible server first."),
                dismissButton: .default(Text("common.confirm".localized()))
            )
        }
    }
}
