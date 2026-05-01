import AppKit
import SwiftUI

public enum GeneralSettingsSection: Hashable {
  case basic
  case update
  case safety
  case backup
}

public struct GeneralSettingsView: View {
  @StateObject var generalSettings = GeneralSettingsManager.shared
  @EnvironmentObject var gameRepository: GameRepository
  @EnvironmentObject var appUpdateService: AppUpdateService
  @State var showDirectoryPicker = false
  @State var showBackupDirectoryPicker = false
  @State var error: GlobalError?
  @State var backupAlertMessage = ""
  @State var showBackupAlert = false
  @State var isRunningManualBackup = false
  @State var showRestoreSheet = false
  @State var restoreBackups: [BackupService.BackupEntry] = []
  @State var selectedBackupId: BackupService.BackupEntry.ID?
  @State var availableRestoreServers: [String] = []
  @State var selectedRestoreServer = ""
  @State var isRestoring = false
  @State var showRestoreConfirm = false
  @State var restoreAlertMessage = ""
  @State var showRestoreAlert = false
  @State var restoreRestartMessage = ""
  @State var showRestoreRestartAlert = false
  @State var hasRestorePoints = false
  /// 数据库中所有工作路径及对应游戏数量（用于快速切换）
  @State var workingPathOptions: [(path: String, count: Int)] = []

  let defaultWorkingDirectory = AppPaths.launcherSupportDirectory.path
  let defaultConcurrentDownloads = 64
  let defaultEnableGitHubProxy = true
  let defaultGitHubProxyURL = "https://gh-proxy.com"
  let defaultEnableResourcePageCache = true
  let defaultLaunchAtLoginEnabled = false
  let defaultUpdateAutoCheckEnabled = true
  let defaultUpdateAutoDownloadEnabled = false
  let defaultConfirmDeleteServer = true
  let defaultConfirmDeleteWorld = true
  let defaultConfirmUninstallPluginMod = true
  let defaultConfirmExitWhileRunning = true
  let defaultAutoAcceptServerEULA = false
  let defaultBackupAutoEnabled = false
  let defaultBackupIntervalMinutes = 60
  let defaultBackupKeepCount = 10
  let defaultBackupBeforeUpdate = true
  let defaultBackupDirectory = AppPaths.launcherSupportDirectory
    .appendingPathComponent("backups", isDirectory: true).path
  let sections: Set<GeneralSettingsSection>

  public init(sections: Set<GeneralSettingsSection> = [.basic, .update, .safety, .backup]) {
    self.sections = sections
  }

  public var body: some View {
    Form {
      if sections.contains(.basic) {
        Section(
          header: Text("settings.general.section.general.header".localized())
        ) {
          LabeledContent("settings.language.picker".localized()) {
            Button {
              SystemSettings.open(AppConstants.SystemSettingsDeepLinks.localizationApps)
            } label: {
              Text(LanguageManager.shared.selectedLanguageDisplayName)
                .foregroundColor(.primary)
                .lineLimit(1)
            }
            .help("settings.language.picker".localized())
          }
          .labeledContentStyle(.custom)
          .padding(.bottom, 4)

          LabeledContent("settings.launcher_working_directory".localized()) {
            HStack(alignment: .top, spacing: 8) {
              VStack(alignment: .leading, spacing: 8) {
                DirectorySettingRow(
                  title: "settings.launcher_working_directory".localized(),
                  path: generalSettings.launcherWorkingDirectory.isEmpty
                    ? defaultWorkingDirectory
                    : generalSettings.launcherWorkingDirectory,
                  description: "settings.working_directory.description".localized(),
                  onChoose: { showDirectoryPicker = true },
                  onReset: { resetWorkingDirectorySafely() },
                  showsResetButton: false
                )
                .fileImporter(
                  isPresented: $showDirectoryPicker,
                  allowedContentTypes: [.folder],
                  allowsMultipleSelection: false
                ) { result in
                  handleDirectoryImport(result)
                }
              }

              resetIconButton(
                disabled: generalSettings.launcherWorkingDirectory == defaultWorkingDirectory
              ) {
                resetWorkingDirectorySafely()
              }
            }
          }
          .labeledContentStyle(.custom(alignment: .firstTextBaseline))
          .task {
            workingPathOptions = await gameRepository.fetchAllWorkingPathsWithCounts()
          }
          .onChange(of: generalSettings.launcherWorkingDirectory) { _, _ in
            Task {
              workingPathOptions = await gameRepository.fetchAllWorkingPathsWithCounts()
            }
          }
        }

        Section(
          header: Text("settings.general.section.basic.network.header".localized())
        ) {

        LabeledContent("settings.concurrent_downloads.label".localized()) {
          HStack(alignment: .top, spacing: 8) {
            HStack {
              Slider(
                value: Binding(
                  get: {
                    Double(generalSettings.concurrentDownloads)
                  },
                  set: {
                    generalSettings.concurrentDownloads = Int(
                      $0
                    )
                  }
                ),
                in: 1...64
              )
              .controlSize(.mini)
              .animation(.easeOut(duration: 0.5), value: generalSettings.concurrentDownloads)
              Text("\(generalSettings.concurrentDownloads)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize()
            }
            .frame(width: 200)
            .gridColumnAlignment(.leading)
            .labelsHidden()

            resetIconButton(
              disabled: generalSettings.concurrentDownloads == defaultConcurrentDownloads
            ) {
              generalSettings.concurrentDownloads = defaultConcurrentDownloads
            }
          }
        }
        .labeledContentStyle(.custom)

        LabeledContent("settings.github_proxy.label".localized()) {
          HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading) {
              HStack {
                Toggle(
                  "",
                  isOn: $generalSettings.enableGitHubProxy
                )
                .labelsHidden()
                Text("settings.github_proxy.enable".localized())
                  .font(.callout)
                  .foregroundColor(.primary)
              }
              HStack(spacing: 8) {
                TextField(
                  "",
                  text: $generalSettings.gitProxyURL
                )
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .focusable(false)
                .disabled(!generalSettings.enableGitHubProxy)
                InfoIconWithPopover(text: "settings.github_proxy.description".localized())
              }
            }

            resetIconButton(
              disabled: generalSettings.enableGitHubProxy == defaultEnableGitHubProxy
                && generalSettings.gitProxyURL == defaultGitHubProxyURL
            ) {
              generalSettings.enableGitHubProxy = defaultEnableGitHubProxy
              generalSettings.gitProxyURL = defaultGitHubProxyURL
            }
          }
        }
        .labeledContentStyle(.custom(alignment: .firstTextBaseline))
        .padding(.top, 4)

        LabeledContent("settings.resource_cache.label".localized()) {
          HStack(alignment: .top, spacing: 8) {
            Toggle(
              "settings.resource_cache.enable".localized(),
              isOn: $generalSettings.enableResourcePageCache
            )
            .toggleStyle(.checkbox)

            resetIconButton(
              disabled: generalSettings.enableResourcePageCache == defaultEnableResourcePageCache
            ) {
              generalSettings.enableResourcePageCache = defaultEnableResourcePageCache
            }
          }
        }
        .labeledContentStyle(.custom)
        .padding(.top, 4)
        }
      }

      if sections.contains(.update) {
        Section(
          header: Text("settings.general.section.update.header".localized())
        ) {
          LabeledContent("settings.general.launch_at_login".localized()) {
            HStack(alignment: .top, spacing: 8) {
              Toggle("", isOn: $generalSettings.launchAtLoginEnabled)
                .labelsHidden()

              resetIconButton(
                disabled: generalSettings.launchAtLoginEnabled == defaultLaunchAtLoginEnabled
              ) {
                generalSettings.launchAtLoginEnabled = defaultLaunchAtLoginEnabled
              }
            }
          }
          .labeledContentStyle(.custom)

          LabeledContent("settings.general.update.auto_check".localized()) {
            HStack(alignment: .top, spacing: 8) {
              Toggle("", isOn: $generalSettings.updateAutoCheckEnabled)
                .labelsHidden()

              resetIconButton(
                disabled: generalSettings.updateAutoCheckEnabled == defaultUpdateAutoCheckEnabled
              ) {
                generalSettings.updateAutoCheckEnabled = defaultUpdateAutoCheckEnabled
              }
            }
          }
          .labeledContentStyle(.custom)

          LabeledContent("settings.general.update.auto_download".localized()) {
            HStack(alignment: .top, spacing: 8) {
              Toggle("", isOn: $generalSettings.updateAutoDownloadEnabled)
                .labelsHidden()

              resetIconButton(
                disabled: generalSettings.updateAutoDownloadEnabled
                  == defaultUpdateAutoDownloadEnabled
              ) {
                generalSettings.updateAutoDownloadEnabled = defaultUpdateAutoDownloadEnabled
              }
            }
          }
          .labeledContentStyle(.custom)
        }
      }

      if sections.contains(.safety) {
        Section(
          header: Text("settings.general.section.safety.header".localized())
        ) {
          LabeledContent("settings.general.confirm.delete_server".localized()) {
            HStack(alignment: .top, spacing: 8) {
              Toggle("", isOn: $generalSettings.confirmDeleteServer)
                .labelsHidden()

              resetIconButton(
                disabled: generalSettings.confirmDeleteServer == defaultConfirmDeleteServer
              ) {
                generalSettings.confirmDeleteServer = defaultConfirmDeleteServer
              }
            }
          }
          .labeledContentStyle(.custom)

          LabeledContent("settings.general.confirm.delete_world".localized()) {
            HStack(alignment: .top, spacing: 8) {
              Toggle("", isOn: $generalSettings.confirmDeleteWorld)
                .labelsHidden()

              resetIconButton(
                disabled: generalSettings.confirmDeleteWorld == defaultConfirmDeleteWorld
              ) {
                generalSettings.confirmDeleteWorld = defaultConfirmDeleteWorld
              }
            }
          }
          .labeledContentStyle(.custom)

          LabeledContent("settings.general.confirm.uninstall_resource".localized()) {
            HStack(alignment: .top, spacing: 8) {
              Toggle("", isOn: $generalSettings.confirmUninstallPluginMod)
                .labelsHidden()

              resetIconButton(
                disabled: generalSettings.confirmUninstallPluginMod
                  == defaultConfirmUninstallPluginMod
              ) {
                generalSettings.confirmUninstallPluginMod = defaultConfirmUninstallPluginMod
              }
            }
          }
          .labeledContentStyle(.custom)

          LabeledContent("settings.general.confirm.exit_running".localized()) {
            HStack(alignment: .top, spacing: 8) {
              Toggle("", isOn: $generalSettings.confirmExitWhileRunning)
                .labelsHidden()

              resetIconButton(
                disabled: generalSettings.confirmExitWhileRunning == defaultConfirmExitWhileRunning
              ) {
                generalSettings.confirmExitWhileRunning = defaultConfirmExitWhileRunning
              }
            }
          }
          .labeledContentStyle(.custom)

          LabeledContent("settings.general.eula.auto_accept".localized()) {
            HStack(alignment: .top, spacing: 8) {
              Toggle("", isOn: $generalSettings.autoAcceptServerEULA)
                .labelsHidden()

              resetIconButton(
                disabled: generalSettings.autoAcceptServerEULA == defaultAutoAcceptServerEULA
              ) {
                generalSettings.autoAcceptServerEULA = defaultAutoAcceptServerEULA
              }
            }
          }
          .labeledContentStyle(.custom)
        }
      }

      if sections.contains(.backup) {
        Section(
          header: Text("settings.general.section.backup.header".localized())
        ) {
          LabeledContent("settings.general.backup.enable".localized()) {
            HStack(alignment: .top, spacing: 8) {
              Toggle("", isOn: $generalSettings.backupAutoEnabled)
                .labelsHidden()

              resetIconButton(
                disabled: generalSettings.backupAutoEnabled == defaultBackupAutoEnabled
              ) {
                generalSettings.backupAutoEnabled = defaultBackupAutoEnabled
              }
            }
          }
          .labeledContentStyle(.custom)

          LabeledContent("settings.general.backup.before_update".localized()) {
            HStack(alignment: .top, spacing: 8) {
              Toggle("", isOn: $generalSettings.backupBeforeUpdate)
                .labelsHidden()

              resetIconButton(
                disabled: generalSettings.backupBeforeUpdate == defaultBackupBeforeUpdate
              ) {
                generalSettings.backupBeforeUpdate = defaultBackupBeforeUpdate
              }
            }
          }
          .labeledContentStyle(.custom)
        }

        Section(
          header: Text("settings.general.section.backup.schedule.header".localized())
        ) {
          LabeledContent("settings.general.backup.interval_minutes".localized()) {
            HStack(alignment: .top, spacing: 8) {
              Text("\(generalSettings.backupIntervalMinutes)")
                .frame(minWidth: 56, alignment: .trailing)
                .monospacedDigit()
              Stepper("", value: $generalSettings.backupIntervalMinutes, in: 5...1440)
                .labelsHidden()

              resetIconButton(
                disabled: generalSettings.backupIntervalMinutes == defaultBackupIntervalMinutes
              ) {
                generalSettings.backupIntervalMinutes = defaultBackupIntervalMinutes
              }
            }
          }
          .labeledContentStyle(.custom)

          LabeledContent("settings.general.backup.keep_count".localized()) {
            HStack(alignment: .top, spacing: 8) {
              Text("\(generalSettings.backupKeepCount)")
                .frame(minWidth: 56, alignment: .trailing)
                .monospacedDigit()
              Stepper("", value: $generalSettings.backupKeepCount, in: 1...200)
                .labelsHidden()

              resetIconButton(disabled: generalSettings.backupKeepCount == defaultBackupKeepCount) {
                generalSettings.backupKeepCount = defaultBackupKeepCount
              }
            }
          }
          .labeledContentStyle(.custom)
        }

        Section(
          header: Text("settings.general.section.backup.storage.header".localized())
        ) {
          LabeledContent("settings.general.backup.directory".localized()) {
            HStack(alignment: .top, spacing: 8) {
              DirectorySettingRow(
                title: "settings.general.backup.directory".localized(),
                path: generalSettings.backupDirectoryPath,
                description: "settings.general.backup.directory.description".localized(),
                onChoose: { showBackupDirectoryPicker = true },
                onReset: {
                  generalSettings.backupDirectoryPath = defaultBackupDirectory
                },
                showsResetButton: false
              )
              .fileImporter(
                isPresented: $showBackupDirectoryPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
              ) { result in
                handleBackupDirectoryImport(result)
              }

              resetIconButton(
                disabled: generalSettings.backupDirectoryPath == defaultBackupDirectory
              ) {
                generalSettings.backupDirectoryPath = defaultBackupDirectory
              }
            }
          }
          .labeledContentStyle(.custom(alignment: .firstTextBaseline))
        }

        Section(
          header: Text("settings.general.section.backup.restore.header".localized())
        ) {
          LabeledContent("settings.general.backup.manual".localized()) {
            HStack(alignment: .top, spacing: 8) {
              Button(
                isRunningManualBackup
                  ? "settings.general.backup.running".localized()
                  : "settings.general.backup.run_now".localized()
              ) {
                runManualBackup()
              }
              .disabled(isRunningManualBackup)
              .buttonStyle(.borderedProminent)

              if generalSettings.backupLastTimestamp > 0 {
                Text(
                  String(
                    format: "settings.general.backup.last_format".localized(),
                    formattedDate(generalSettings.backupLastTimestamp)
                  )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
              }
            }
          }
          .labeledContentStyle(.custom)

          if hasRestorePoints {
            LabeledContent("settings.general.backup.restore.title".localized()) {
              HStack(alignment: .top, spacing: 8) {
                Button("settings.general.backup.restore.action".localized()) {
                  loadRestoreBackups()
                  showRestoreSheet = true
                }
                .buttonStyle(.bordered)
              }
            }
            .labeledContentStyle(.custom)
          }
        }
      }
    }
    .onAppear {
      applyLaunchAtLoginPreference()
      appUpdateService.applyUserPreferences()
      BackupService.shared.reloadAutoBackupScheduler()
      refreshRestoreAvailability()
    }
    .onChange(of: generalSettings.launchAtLoginEnabled) { _, _ in
      applyLaunchAtLoginPreference()
    }
    .onChange(of: generalSettings.updateAutoCheckEnabled) { _, _ in
      appUpdateService.applyUserPreferences()
    }
    .onChange(of: generalSettings.updateAutoDownloadEnabled) { _, _ in
      appUpdateService.applyUserPreferences()
    }
    .onChange(of: generalSettings.backupAutoEnabled) { _, _ in
      BackupService.shared.reloadAutoBackupScheduler()
    }
    .onChange(of: generalSettings.backupIntervalMinutes) { _, _ in
      BackupService.shared.reloadAutoBackupScheduler()
    }
    .onChange(of: generalSettings.backupDirectoryPath) { _, _ in
      BackupService.shared.reloadAutoBackupScheduler()
    }
    .onChange(of: generalSettings.backupKeepCount) { _, _ in
      BackupService.shared.reloadAutoBackupScheduler()
    }
    .formStyle(.grouped)
    .globalErrorHandler()
    .alert(
      "error.notification.validation.title".localized(),
      isPresented: .constant(error != nil && error?.level == .popup)
    ) {
      Button("common.close".localized()) {
        error = nil
      }
    } message: {
      if let error = error {
        Text(error.localizedDescription)
      }
    }
    .alert("settings.general.backup.alert.title".localized(), isPresented: $showBackupAlert) {
      Button("common.ok".localized(), role: .cancel) {}
    } message: {
      Text(backupAlertMessage)
    }
    .alert(
      "settings.general.backup.restore.alert.title".localized(),
      isPresented: $showRestoreAlert
    ) {
      Button("common.ok".localized(), role: .cancel) {}
    } message: {
      Text(restoreAlertMessage)
    }
    .alert(
      "settings.general.backup.restore.restart.title".localized(),
      isPresented: $showRestoreRestartAlert
    ) {
      Button("settings.language.restart.confirm".localized(), role: .destructive) {
        restartAppSafely()
      }
      Button("common.cancel".localized(), role: .cancel) {}
    } message: {
      Text(restoreRestartMessage)
    }
    .sheet(isPresented: $showRestoreSheet) {
      restoreSheet
    }
  }
}
