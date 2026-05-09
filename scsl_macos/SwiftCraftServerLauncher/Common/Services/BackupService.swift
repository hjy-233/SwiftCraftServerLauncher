import Foundation

@MainActor
final class BackupService: ObservableObject {
  static let shared = BackupService()

  private struct BackupEntryCLIResponse: Decodable {
    let path: String
    let modifiedAt: Double
  }

  private struct BackupRestoreCLIResponse: Decodable {
    let createdServer: Bool
  }

  struct BackupEntry: Identifiable {
    let id = UUID()
    let url: URL
    let createdAt: Date
  }

  private var timer: Timer?
  private let formatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter
  }()

  private init() {}

  func startAutoBackupScheduler() {
    reloadAutoBackupScheduler()
  }

  func reloadAutoBackupScheduler() {
    timer?.invalidate()
    timer = nil

    let settings = GeneralSettingsManager.shared
    guard settings.backupAutoEnabled else { return }

    let interval = TimeInterval(max(5, settings.backupIntervalMinutes) * 60)
    timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
      Task { @MainActor in
        do {
          _ = try await self.createBackup(reason: "auto")
        } catch {
          Logger.shared.error("自动备份失败: \(error.localizedDescription)")
        }
      }
    }
  }

  func createBackup(reason: String) async throws -> URL {
    let settings = GeneralSettingsManager.shared
    let fileManager = FileManager.default

    // 仅备份 servers 目录，避免把整个工作目录都打包进去。
    let sourceRoot = AppPaths.serverRootDirectory
    if !fileManager.fileExists(atPath: sourceRoot.path) {
      try fileManager.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
    }

    let backupRoot = resolvedBackupDirectory()
    try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)

    let timestamp = formatter.string(from: Date())
    let outputURL = backupRoot.appendingPathComponent(
      "swiftcraft-backup-\(reason)-\(timestamp).zip",
      isDirectory: false
    )

    if fileManager.fileExists(atPath: outputURL.path) {
      try fileManager.removeItem(at: outputURL)
    }

    let _: ScslCoreCLIEnvelope<ResourceDownloadCLIResponse> = try await ScslCoreCLIService.shared.runJSON(
      arguments: [
        "game", "backup-create",
        "--source-root", sourceRoot.path,
        "--output-path", outputURL.path,
        "--keep-count", String(settings.backupKeepCount),
      ]
    )

    settings.backupLastTimestamp = Date().timeIntervalSince1970
    Logger.shared.info("创建 servers 备份成功: \(outputURL.path)")
    return outputURL
  }

  func createBackupBeforeUpdateIfNeeded() async throws -> URL? {
    let settings = GeneralSettingsManager.shared
    guard settings.backupBeforeUpdate else { return nil }
    return try await createBackup(reason: "before-update")
  }

  func listBackups() -> [BackupEntry] {
    for root in backupCandidates() {
      let entries = listBackups(in: root)
      if !entries.isEmpty {
        return entries
      }
    }

    return []
  }

  private func listBackups(in backupRoot: URL) -> [BackupEntry] {
    let result: [BackupEntryCLIResponse]
    do {
      let envelope: ScslCoreCLIEnvelope<[BackupEntryCLIResponse]> = try runScslCLIJSONSync(
        arguments: ["game", "backup-list", "--backup-root", backupRoot.path]
      )
      result = envelope.data
    } catch {
      return []
    }
    return result.compactMap { item in
      let url = URL(fileURLWithPath: item.path)
      return BackupEntry(
        url: url,
        createdAt: Date(timeIntervalSince1970: item.modifiedAt)
      )
    }
  }

  private func appendCandidate(_ url: URL, to list: inout [URL]) {
    if !list.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) {
      list.append(url)
    }
  }

  private func backupCandidates() -> [URL] {
    let backupRoot = resolvedBackupDirectory()
    let defaultRoot = AppPaths.launcherSupportDirectory
      .appendingPathComponent("backups", isDirectory: true)
    let legacyRoot = legacyBackupDirectory()

    var candidates: [URL] = []
    for url in [backupRoot, defaultRoot, legacyRoot].compactMap({ $0 }) {
      appendCandidate(url, to: &candidates)
      if url.lastPathComponent.lowercased() != "backups" {
        appendCandidate(url.appendingPathComponent("backups", isDirectory: true), to: &candidates)
      }
    }
    return candidates
  }

  private func legacyBackupDirectory() -> URL? {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let legacySupport = home.appendingPathComponent("Library/Application Support", isDirectory: true)
    return legacySupport.appendingPathComponent(Bundle.main.appName)
      .appendingPathComponent("backups", isDirectory: true)
  }

  func listServers(in backupURL: URL) -> [String] {
    do {
      let envelope: ScslCoreCLIEnvelope<[String]> = try runScslCLIJSONSync(
        arguments: ["game", "backup-list-servers", "--backup-path", backupURL.path]
      )
      return envelope.data
    } catch {
      return []
    }
  }

  struct RestoreResult {
    let createdServer: Bool
  }

  func restoreServer(named serverName: String, from backupURL: URL) throws -> RestoreResult {
    let targetRoot = AppPaths.serverRootDirectory
    let envelope: ScslCoreCLIEnvelope<BackupRestoreCLIResponse> = try runScslCLIJSONSync(
      arguments: [
        "game", "backup-restore",
        "--backup-path", backupURL.path,
        "--server-name", serverName,
        "--target-root", targetRoot.path,
      ]
    )
    let targetServerPath = targetRoot.appendingPathComponent(serverName, isDirectory: true)
    let createdServer = try ensureServerRecord(serverName: serverName, serverPath: targetServerPath)
    _ = envelope
    return RestoreResult(createdServer: createdServer)
  }

  private func resolvedBackupDirectory() -> URL {
    let settings = GeneralSettingsManager.shared
    let rawPath = settings.backupDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
    let expandedPath = (rawPath as NSString).expandingTildeInPath
    if rawPath.isEmpty {
      return AppPaths.launcherSupportDirectory.appendingPathComponent("backups", isDirectory: true)
    }
    return URL(fileURLWithPath: expandedPath, isDirectory: true)
  }

  private func ensureServerRecord(serverName: String, serverPath: URL) throws -> Bool {
    let dbPath = AppPaths.gameVersionDatabase.path
    let workingPath = GeneralSettingsManager.shared.currentWorkingPath
    let database = ServerDatabase(dbPath: dbPath)
    try database.initialize()

    let existing = try database.loadServers(workingPath: workingPath)
    if existing.contains(where: { $0.name == serverName }) {
      return false
    }

    let jarName = findServerJar(in: serverPath) ?? ""
    let server = ServerInstance(
      name: serverName,
      serverType: .custom,
      gameVersion: "unknown",
      loaderVersion: "",
      serverJar: jarName,
      lastPlayed: Date()
    )
    try database.saveServer(server, workingPath: workingPath)
    return true
  }

  private func findServerJar(in serverPath: URL) -> String? {
    let files =
      (try? FileManager.default.contentsOfDirectory(
        at: serverPath,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )) ?? []
    return files.first { $0.pathExtension.lowercased() == "jar" }?.lastPathComponent
  }
}

private struct ResourceDownloadCLIResponse: Decodable {
  let path: String
}

private func runScslCLIJSONSync<T: Decodable>(
  arguments: [String],
  standardInput: String? = nil
) throws -> ScslCoreCLIEnvelope<T> {
  let semaphore = DispatchSemaphore(value: 0)
  var result: Result<ScslCoreCLIEnvelope<T>, Error>?

  Task {
    defer { semaphore.signal() }
    do {
      result = .success(try await ScslCoreCLIService.shared.runJSON(
        arguments: arguments,
        standardInput: standardInput
      ))
    } catch {
      result = .failure(error)
    }
  }

  semaphore.wait()
  switch result {
  case .success(let envelope):
    return envelope
  case .failure(let error):
    throw error
  case .none:
    throw ScslCoreCLIError.executionFailed("未收到 scsl_cli 返回结果")
  }
}
