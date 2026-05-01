import Foundation
import ZIPFoundation

@MainActor
final class BackupService: ObservableObject {
  static let shared = BackupService()

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

    try await archiveDirectory(sourceRoot: sourceRoot, outputURL: outputURL)
    try pruneBackups(keepCount: settings.backupKeepCount, backupRoot: backupRoot)

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
    let fileManager = FileManager.default
    let path = backupRoot.path
    guard fileManager.fileExists(atPath: path) else {
      return []
    }
    guard fileManager.isReadableFile(atPath: path) else {
      return []
    }

    let urls: [URL]
    do {
      urls = try fileManager.contentsOfDirectory(
        at: backupRoot,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )
    } catch {
      return []
    }

    let entries: [BackupEntry] = urls.compactMap { url in
      guard url.pathExtension.lowercased() == "zip" else { return nil }
      let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
      let date = values?.contentModificationDate ?? .distantPast
      return BackupEntry(url: url, createdAt: date)
    }

    return entries.sorted { $0.createdAt > $1.createdAt }
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
    let archive: Archive
    do {
      archive = try Archive(url: backupURL, accessMode: .read)
    } catch {
      return []
    }
    let prefix = "servers/"
    var names = Set<String>()

    for entry in archive {
      let path = entry.path
      guard path.hasPrefix(prefix) else { continue }
      let rest = String(path.dropFirst(prefix.count))
      guard !rest.isEmpty else { continue }
      // 只识别 servers/<name>/... 这种路径，忽略 servers 下的文件。
      guard rest.contains("/") else { continue }
      let firstComponent = rest.split(separator: "/").first.map(String.init)
      guard let name = firstComponent, !name.isEmpty else { continue }
      if name.hasPrefix(".") { continue }
      if name == ".DS_Store" { continue }
      names.insert(name)
    }

    return names.sorted()
  }

  struct RestoreResult {
    let createdServer: Bool
  }

  func restoreServer(named serverName: String, from backupURL: URL) throws -> RestoreResult {
    let archive = try Archive(url: backupURL, accessMode: .read)

    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(
      "swiftcraft-restore-\(UUID().uuidString)",
      isDirectory: true
    )
    try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)

    let prefix = "servers/\(serverName)/"
    for entry in archive {
      let path = entry.path
      guard path.hasPrefix(prefix) else { continue }
      let destinationURL = tempRoot.appendingPathComponent(
        path,
        isDirectory: entry.type == .directory
      )
      try fileManager.createDirectory(
        at: destinationURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      _ = try archive.extract(entry, to: destinationURL)
    }

    let restoredServerPath = tempRoot.appendingPathComponent("servers", isDirectory: true)
      .appendingPathComponent(serverName, isDirectory: true)
    guard fileManager.fileExists(atPath: restoredServerPath.path) else {
      throw NSError(
        domain: "BackupService",
        code: 3,
        userInfo: [NSLocalizedDescriptionKey: "备份中未找到指定服务器"]
      )
    }

    let targetRoot = AppPaths.serverRootDirectory
    let targetServerPath = targetRoot.appendingPathComponent(serverName, isDirectory: true)
    if fileManager.fileExists(atPath: targetServerPath.path) {
      try fileManager.removeItem(at: targetServerPath)
    }
    try fileManager.createDirectory(at: targetRoot, withIntermediateDirectories: true)
    try fileManager.moveItem(at: restoredServerPath, to: targetServerPath)
    try? fileManager.removeItem(at: tempRoot)

    let createdServer = try ensureServerRecord(serverName: serverName, serverPath: targetServerPath)
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

  private func archiveDirectory(sourceRoot: URL, outputURL: URL) async throws {
    try await withCheckedThrowingContinuation { continuation in
      let process = Process()
      let stderrPipe = Pipe()

      process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
      process.arguments = [
        "-c",
        "-k",
        "--keepParent",
        sourceRoot.path,
        outputURL.path,
      ]
      process.standardError = stderrPipe

      process.terminationHandler = { process in
        let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput =
          String(data: errorData, encoding: .utf8)?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus == 0 {
          continuation.resume()
        } else {
          let message =
            errorOutput.isEmpty
            ? "ditto 备份失败，退出码: \(process.terminationStatus)"
            : errorOutput
          continuation.resume(
            throwing: NSError(
              domain: "BackupService",
              code: Int(process.terminationStatus),
              userInfo: [NSLocalizedDescriptionKey: message]
            )
          )
        }
      }

      do {
        try process.run()
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }

  private func pruneBackups(keepCount: Int, backupRoot: URL) throws {
    let fileManager = FileManager.default
    let files = try fileManager.contentsOfDirectory(
      at: backupRoot,
      includingPropertiesForKeys: [.contentModificationDateKey],
      options: [.skipsHiddenFiles]
    )
    .filter { $0.pathExtension.lowercased() == "zip" }
    .sorted { lhs, rhs in
      let lDate =
        (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        ?? .distantPast
      let rDate =
        (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        ?? .distantPast
      return lDate > rDate
    }

    if files.count <= keepCount { return }
    for oldFile in files.dropFirst(keepCount) {
      try? fileManager.removeItem(at: oldFile)
    }
  }
}
