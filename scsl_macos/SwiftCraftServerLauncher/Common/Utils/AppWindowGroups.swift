import SwiftUI

/// 应用窗口组定义
extension SwiftCraftServerLauncherApp {
    /// 创建所有应用窗口组
    @SceneBuilder
    func appWindowGroups() -> some Scene {
        Window(String(format: "menu.about".localized(), Bundle.main.appName), id: WindowID.about.rawValue) {
            AboutView()
                .windowStyleConfig(for: .about)
                .windowCleanup(for: .about)
        }
        .defaultSize(width: 560, height: 220)

        Window("about.contributors".localized(), id: WindowID.contributors.rawValue) {
            ContributorsView()
                .frame(width: 560, height: 500)
            .windowStyleConfig(for: .contributors)
            .windowCleanup(for: .contributors)
        }
        .defaultSize(width: 600, height: 540)

        // 下载中心窗口
        Window("download.center".localized(), id: WindowID.downloadCenter.rawValue) {
            DownloadCenterWindowView()
                .windowStyleConfig(for: .downloadCenter)
                .windowCleanup(for: .downloadCenter)
        }
        .defaultSize(width: 520, height: 420)
    }
}
