import AppKit
import SwiftUI

extension GeneralSettingsView {
  // MARK: - Private Methods

  /// 工作路径选择框展示文案：路径最后一段 + 游戏个数
  func workingPathDisplayString(for item: (path: String, count: Int)) -> String {
    let lastComponent = (item.path as NSString).lastPathComponent
    let countStr = String(format: "settings.working_path.game_count".localized(), item.count)
    return "\(lastComponent) (\(countStr))"
  }

  /// 安全地重置工作目录
  func resetWorkingDirectorySafely() {
    do {
      let appSupportDirectory = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first

      guard let supportDir = appSupportDirectory?.appendingPathComponent(Bundle.main.appName) else {
        throw GlobalError.configuration(
          chineseMessage: "无法获取应用支持目录",
          i18nKey: "error.configuration.app_support_directory_not_found",
          level: .popup
        )
      }

      // 确保目录存在
      try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)

      generalSettings.launcherWorkingDirectory = supportDir.path

      Logger.shared.info("工作目录已重置为: \(supportDir.path)")
    } catch {
      let globalError = GlobalError.from(error)
      GlobalErrorHandler.shared.handle(globalError)
      self.error = globalError
    }
  }

  /// 处理目录导入结果
  func handleDirectoryImport(_ result: Result<[URL], Error>) {
    switch result {
    case .success(let urls):
      if let url = urls.first {
        do {
          // 验证目录是否可访问
          let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey])
          guard resourceValues.isDirectory == true, resourceValues.isReadable == true else {
            throw GlobalError.fileSystem(
              chineseMessage: "选择的路径不是可读的目录",
              i18nKey: "error.filesystem.invalid_directory_selected",
              level: .notification
            )
          }

          generalSettings.launcherWorkingDirectory = url.path
          // GameRepository 观察者会自动重新加载，无需手动 loadGames

          Logger.shared.info("工作目录已设置为: \(url.path)")
        } catch {
          let globalError = GlobalError.from(error)
          GlobalErrorHandler.shared.handle(globalError)
          self.error = globalError
        }
      }
    case .failure(let error):
      let globalError = GlobalError.fileSystem(
        chineseMessage: "选择目录失败: \(error.localizedDescription)",
        i18nKey: "error.filesystem.directory_selection_failed",
        level: .notification
      )
      GlobalErrorHandler.shared.handle(globalError)
      self.error = globalError
    }
  }

  /// 安全地重启应用
  func restartAppSafely() {
    do {
      try restartApp()
    } catch {
      let globalError = GlobalError.from(error)
      GlobalErrorHandler.shared.handle(globalError)
      self.error = globalError
    }
  }

  func applyLaunchAtLoginPreference() {
    do {
      try LaunchAtLoginManager.shared.applyPreference(enabled: generalSettings.launchAtLoginEnabled)
    } catch {
      GlobalErrorHandler.shared.handle(error)
    }
  }

  func handleBackupDirectoryImport(_ result: Result<[URL], Error>) {
    switch result {
    case .success(let urls):
      guard let url = urls.first else { return }
      do {
        let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey])
        guard resourceValues.isDirectory == true, resourceValues.isReadable == true else {
          throw GlobalError.fileSystem(
            chineseMessage: "备份目录不可访问",
            i18nKey: "error.filesystem.invalid_directory_selected",
            level: .notification
          )
        }
        generalSettings.backupDirectoryPath = url.path
        BackupService.shared.reloadAutoBackupScheduler()
      } catch {
        GlobalErrorHandler.shared.handle(error)
      }
    case .failure(let error):
      GlobalErrorHandler.shared.handle(error)
    }
  }

  func runManualBackup() {
    guard !isRunningManualBackup else { return }
    isRunningManualBackup = true
    Task { @MainActor in
      defer { isRunningManualBackup = false }
      do {
        let backupURL = try await BackupService.shared.createBackup(reason: "manual")
        backupAlertMessage = String(
          format: "settings.general.backup.alert.success".localized(),
          backupURL.path
        )
      } catch {
        backupAlertMessage = String(
          format: "settings.general.backup.alert.failure".localized(),
          error.localizedDescription
        )
      }
      refreshRestoreAvailability()
      showBackupAlert = true
    }
  }

  func formattedDate(_ timestamp: Double) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.string(from: Date(timeIntervalSince1970: timestamp))
  }

  func loadRestoreBackups() {
    let backups = BackupService.shared.listBackups()
    restoreBackups = backups
    hasRestorePoints = !backups.isEmpty
    if let first = backups.first {
      selectedBackupId = first.id
      availableRestoreServers = BackupService.shared.listServers(in: first.url)
      selectedRestoreServer = availableRestoreServers.first ?? ""
    } else {
      selectedBackupId = nil
      availableRestoreServers = []
      selectedRestoreServer = ""
    }
  }

  func refreshRestoreAvailability() {
    hasRestorePoints = !BackupService.shared.listBackups().isEmpty
  }

  func backupLabel(for entry: BackupService.BackupEntry) -> String {
    if let parsed = parseBackupLabel(entry.url.lastPathComponent) {
      return parsed
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let dateString = formatter.string(from: entry.createdAt)
    return "\(entry.url.lastPathComponent) (\(dateString))"
  }

  func parseBackupLabel(_ fileName: String) -> String? {
    let baseName = (fileName as NSString).deletingPathExtension
    let prefix = "swiftcraft-backup-"
    guard baseName.hasPrefix(prefix) else { return nil }

    let remainder = String(baseName.dropFirst(prefix.count))
    let parts = remainder.split(separator: "-")
    guard let reasonPart = parts.first else { return nil }

    let reason = String(reasonPart)
    let timestampPart = parts.dropFirst().joined(separator: "-")
    guard let date = parseBackupTimestamp(timestampPart) else { return nil }

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let dateString = formatter.string(from: date)

    let reasonLabel: String
    switch reason {
    case "manual":
      reasonLabel = "backup.reason.manual".localized()
    case "auto":
      reasonLabel = "backup.reason.auto".localized()
    case "before-update":
      reasonLabel = "backup.reason.before_update".localized()
    default:
      reasonLabel = "backup.reason.default".localized()
    }

    return "\(reasonLabel) · \(dateString)"
  }

  func parseBackupTimestamp(_ raw: String) -> Date? {
    let pattern = "(\\d{8}).*?(\\d{6})"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(location: 0, length: raw.utf16.count)
    guard let match = regex.firstMatch(in: raw, range: range) else { return nil }
    guard
      let dateRange = Range(match.range(at: 1), in: raw),
      let timeRange = Range(match.range(at: 2), in: raw)
    else {
      return nil
    }

    let dateStr = String(raw[dateRange])
    let timeStr = String(raw[timeRange])
    guard dateStr.count == 8, timeStr.count == 6 else { return nil }

    let year = Int(dateStr.prefix(4)) ?? 0
    let month = Int(dateStr.dropFirst(4).prefix(2)) ?? 0
    let day = Int(dateStr.dropFirst(6).prefix(2)) ?? 0
    var hour = Int(timeStr.prefix(2)) ?? 0
    let minute = Int(timeStr.dropFirst(2).prefix(2)) ?? 0
    let second = Int(timeStr.dropFirst(4).prefix(2)) ?? 0

    if raw.contains("下午") || raw.lowercased().contains("pm") {
      if hour < 12 { hour += 12 }
    } else if raw.contains("上午") || raw.lowercased().contains("am") {
      if hour == 12 { hour = 0 }
    }

    var components = DateComponents()
    components.calendar = Calendar.current
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    return components.date
  }

  func selectedBackupURL() -> URL? {
    restoreBackups.first { $0.id == selectedBackupId }?.url
  }

  func updateServersForSelection() {
    guard let backupURL = selectedBackupURL() else {
      availableRestoreServers = []
      selectedRestoreServer = ""
      return
    }
    availableRestoreServers = BackupService.shared.listServers(in: backupURL)
    if !availableRestoreServers.contains(selectedRestoreServer) {
      selectedRestoreServer = availableRestoreServers.first ?? ""
    }
  }

  func performRestore() {
    guard let backupURL = selectedBackupURL(), !selectedRestoreServer.isEmpty else { return }
    guard !isRestoring else { return }
    isRestoring = true
    Task { @MainActor in
      defer { isRestoring = false }
      do {
        let result = try BackupService.shared.restoreServer(
          named: selectedRestoreServer,
          from: backupURL
        )
        if result.createdServer {
          restoreRestartMessage = String(
            format: "settings.general.backup.restore.restart.message".localized(),
            selectedRestoreServer
          )
          showRestoreRestartAlert = true
        } else {
          restoreAlertMessage = String(
            format: "settings.general.backup.restore.success".localized(),
            selectedRestoreServer
          )
          showRestoreAlert = true
        }
      } catch {
        restoreAlertMessage = String(
          format: "settings.general.backup.restore.failure".localized(),
          error.localizedDescription
        )
        showRestoreAlert = true
      }
      refreshRestoreAvailability()
    }
  }

  var restoreSheet: some View {
    CommonSheetView(
      header: {
        HStack {
          Text("settings.general.backup.restore.sheet.title".localized())
            .font(.headline)
          Spacer()
          Button("settings.general.backup.restore.refresh".localized()) {
            loadRestoreBackups()
          }
        }
      },
      body: {
        VStack(alignment: .leading, spacing: 16) {
          LabeledContent("settings.general.backup.restore.backup_picker".localized()) {
            Picker("", selection: $selectedBackupId) {
              ForEach(restoreBackups) { entry in
                Text(backupLabel(for: entry)).tag(entry.id as BackupService.BackupEntry.ID?)
              }
            }
            .labelsHidden()
            .frame(maxWidth: 420)
            .onChange(of: selectedBackupId) { _, _ in
              updateServersForSelection()
            }
          }
          .labeledContentStyle(.automatic)

          LabeledContent("settings.general.backup.restore.server_picker".localized()) {
            Picker("", selection: $selectedRestoreServer) {
              ForEach(availableRestoreServers, id: \.self) { name in
                Text(name).tag(name)
              }
            }
            .labelsHidden()
            .frame(maxWidth: 260)
          }
          .labeledContentStyle(.automatic)

          if restoreBackups.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
              Text("settings.general.backup.restore.empty".localized())
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
          }
        }
      },
      footer: {
        HStack(spacing: 12) {
          Spacer()
          Button("common.cancel".localized()) {
            showRestoreSheet = false
          }
          Button(
            isRestoring
              ? "settings.general.backup.restore.restoring".localized()
              : "settings.general.backup.restore.confirm.action".localized()
          ) {
            showRestoreConfirm = true
          }
          .disabled(isRestoring || selectedRestoreServer.isEmpty || selectedBackupId == nil)
          .buttonStyle(.borderedProminent)
        }
      }
    )
    .frame(width: 680)
    .onAppear {
      if restoreBackups.isEmpty {
        loadRestoreBackups()
      }
    }
    .confirmationDialog(
      "settings.general.backup.restore.confirm.title".localized(),
      isPresented: $showRestoreConfirm,
      titleVisibility: .visible
    ) {
      Button("common.confirm".localized(), role: .destructive) {
        showRestoreSheet = false
        performRestore()
      }
      Button("common.cancel".localized(), role: .cancel) {}
    } message: {
      Text(
        String(
          format: "settings.general.backup.restore.confirm.message".localized(),
          selectedRestoreServer
        )
      )
    }
  }

  @ViewBuilder
  func resetIconButton(disabled: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: "arrow.counterclockwise.circle")
        .font(.title3)
    }
    .buttonStyle(.plain)
    .foregroundStyle(disabled ? .tertiary : .secondary)
    .help("common.reset".localized())
    .disabled(disabled)
  }
}

/// 重启应用
/// - Throws: GlobalError 当重启失败时
func restartApp() throws {
  guard let appURL = Bundle.main.bundleURL as URL? else {
    throw GlobalError.configuration(
      chineseMessage: "无法获取应用路径",
      i18nKey: "error.configuration.app_path_not_found",
      level: .popup
    )
  }

  let task = Process()
  task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
  task.arguments = [appURL.path]

  try task.run()

  DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
    NSApplication.shared.terminate(nil)
  }
}
