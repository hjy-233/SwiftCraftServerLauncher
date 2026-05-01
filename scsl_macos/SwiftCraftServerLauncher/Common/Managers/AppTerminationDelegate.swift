import AppKit
import CoreSpotlight
import Foundation

@MainActor
final class AppTerminationDelegate: NSObject, NSApplicationDelegate {
    func application(
        _ application: NSApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([NSUserActivityRestoring]) -> Void
    ) -> Bool {
        if userActivity.activityType == CSSearchableItemActionType,
           let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
            SpotlightActionCenter.shared.send(identifier: identifier)
            return true
        }
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let settings = GeneralSettingsManager.shared
        guard settings.confirmExitWhileRunning else { return .terminateNow }

        let runningGameCount = GameProcessManager.shared.runningProcessCount()
        let runningServerCount = ServerProcessManager.shared.runningProcessCount()
        guard runningGameCount > 0 || runningServerCount > 0 else { return .terminateNow }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "仍有运行中的实例"
        alert.informativeText = "游戏: \(runningGameCount) 个，服务器: \(runningServerCount) 个。确定要退出吗？"
        alert.addButton(withTitle: "退出")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
}
