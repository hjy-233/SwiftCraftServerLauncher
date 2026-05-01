import AppKit
import Foundation
import Sparkle

@MainActor
final class AppUpdateService: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var isUpdating = false

    private lazy var updaterController: SPUStandardUpdaterController = {
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        _ = controller.updater.clearFeedURLFromUserDefaults()
        return controller
    }()

    override init() {
        super.init()
        applyUserPreferences()
    }

    /// Menu entry keeps its old name to avoid touching call sites.
    func installLatestRelease() {
        guard !isUpdating else { return }

        guard let feedURLString = architectureFeedURLString, !feedURLString.isEmpty else {
            showAlert(
                title: "更新配置缺失",
                message: "当前架构的 Sparkle Appcast 地址无效。"
            )
            return
        }

        isUpdating = true

        Task { @MainActor in
            do {
                _ = try await BackupService.shared.createBackupBeforeUpdateIfNeeded()
            } catch {
                showAlert(title: "备份失败", message: "更新前备份失败：\(error.localizedDescription)")
                isUpdating = false
                return
            }

            applyUserPreferences()
            updaterController.checkForUpdates(nil)

            // Sparkle manages the whole cycle; this flag only throttles rapid repeated taps.
            try? await Task.sleep(nanoseconds: 800_000_000)
            isUpdating = false
        }
    }

    func applyUserPreferences() {
        let settings = GeneralSettingsManager.shared
        updaterController.updater.automaticallyChecksForUpdates = settings.updateAutoCheckEnabled
        updaterController.updater.automaticallyDownloadsUpdates = settings.updateAutoDownloadEnabled
    }

    private var architectureFeedURLString: String? {
        let appcastURL = URLConfig.API.GitHub.appcastURL(
            architecture: Architecture.current.sparkleArch
        )
        let feed = appcastURL.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        return feed.isEmpty ? nil : feed
    }

    func feedURLString(for _: SPUUpdater) -> String? {
        architectureFeedURLString
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
}
