import Combine
import Foundation

class ServerRepository: ObservableObject {
    @Published private(set) var serversByWorkingPath: [String: [ServerInstance]] = [:]
    @Published private(set) var corruptedServersByWorkingPath: [String: [String]] = [:]

    var servers: [ServerInstance] {
        serversByWorkingPath[currentWorkingPath] ?? []
    }

    var corruptedServers: [String] {
        corruptedServersByWorkingPath[currentWorkingPath] ?? []
    }

    private var currentWorkingPath: String {
        workingPathProvider.currentWorkingPath
    }

    private let workingPathProvider: WorkingPathProviding
    private let database: ServerDatabase
    private var workingPathCancellable: AnyCancellable?
    private var lastWorkingPath: String = ""

    @Published var workingPathChanged: Bool = false

    init(workingPathProvider: WorkingPathProviding = GeneralSettingsManager.shared) {
        self.workingPathProvider = workingPathProvider
        let dbPath = AppPaths.gameVersionDatabase.path
        self.database = ServerDatabase(dbPath: dbPath)

        lastWorkingPath = currentWorkingPath

        Task {
            do {
                try await initializeDatabase()
                loadServersSafely()
            } catch {
                GlobalErrorHandler.shared.handle(error)
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.setupWorkingPathObserver()
        }
    }

    private func initializeDatabase() async throws {
        let dataDir = AppPaths.dataDirectory
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        try database.initialize()
    }

    deinit {
        workingPathCancellable?.cancel()
    }

    private func setupWorkingPathObserver() {
        lastWorkingPath = currentWorkingPath

        workingPathCancellable = workingPathProvider.workingPathWillChange
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                let newPath = self.currentWorkingPath
                if newPath != self.lastWorkingPath {
                    self.lastWorkingPath = newPath
                    self.workingPathChanged = true
                    Task { @MainActor in
                        do {
                            try await self.loadServersThrowing()
                            self.workingPathChanged = false
                        } catch {
                            GlobalErrorHandler.shared.handle(error)
                            self.workingPathChanged = false
                        }
                    }
                }
            }
    }

    func addServer(_ server: ServerInstance) async throws {
        let workingPath = currentWorkingPath
        let dbPath = AppPaths.gameVersionDatabase.path
        let serverToSave = server

        try await Task.detached(priority: .userInitiated) {
            let db = ServerDatabase(dbPath: dbPath)
            try? db.initialize()
            try db.saveServer(serverToSave, workingPath: workingPath)
        }.value

        await MainActor.run {
            if serversByWorkingPath[workingPath] == nil {
                serversByWorkingPath[workingPath] = []
            }
            serversByWorkingPath[workingPath]?.removeAll {
                $0.nodeId == server.nodeId && $0.name == server.name && $0.id != server.id
            }
            if let index = serversByWorkingPath[workingPath]?.firstIndex(where: { $0.id == server.id }) {
                serversByWorkingPath[workingPath]?[index] = server
            } else {
                serversByWorkingPath[workingPath]?.append(server)
            }
        }

        Logger.shared.info("成功添加服务器: \(server.name) (工作路径: \(workingPath))")
    }

    func addServerSilently(_ server: ServerInstance) {
        Task {
            do {
                try await addServer(server)
            } catch {
                GlobalErrorHandler.shared.handle(error)
            }
        }
    }

    func deleteServer(id: String) async throws {
        let workingPath = currentWorkingPath
        guard let server = getServer(by: id) else {
            throw GlobalError.validation(
                chineseMessage: "找不到要删除的服务器：\(id)",
                i18nKey: "error.validation.server_not_found_delete",
                level: .notification
            )
        }
        let dbPath = AppPaths.gameVersionDatabase.path

        try await Task.detached(priority: .userInitiated) {
            let db = ServerDatabase(dbPath: dbPath)
            try? db.initialize()
            try db.deleteServer(id: id)
        }.value

        await MainActor.run {
            serversByWorkingPath[workingPath]?.removeAll { $0.id == id }
        }

        Logger.shared.info("成功删除服务器: \(server.name) (工作路径: \(workingPath))")
    }

    func deleteServerSilently(id: String) {
        Task {
            do {
                try await deleteServer(id: id)
            } catch {
                GlobalErrorHandler.shared.handle(error)
            }
        }
    }

    func deleteServersByName(_ serverName: String) async throws {
        let workingPath = currentWorkingPath
        let dbPath = AppPaths.gameVersionDatabase.path

        try await Task.detached(priority: .userInitiated) {
            let db = ServerDatabase(dbPath: dbPath)
            try? db.initialize()
            try db.deleteServers(workingPath: workingPath, serverName: serverName)
        }.value

        await MainActor.run {
            serversByWorkingPath[workingPath]?.removeAll { $0.name == serverName }
            corruptedServersByWorkingPath[workingPath]?.removeAll { $0 == serverName }
        }

        Logger.shared.info("成功删除名称为 \(serverName) 的服务器记录（工作路径: \(workingPath)）")
    }

    func getServer(by id: String) -> ServerInstance? {
        return servers.first { $0.id == id }
    }

    func getServerByName(by name: String) -> ServerInstance? {
        return servers.first { $0.name == name }
    }

    func updateServer(_ server: ServerInstance) async throws {
        let workingPath = currentWorkingPath
        let dbPath = AppPaths.gameVersionDatabase.path
        let serverToSave = server

        try await Task.detached(priority: .userInitiated) {
            let db = ServerDatabase(dbPath: dbPath)
            try? db.initialize()
            try db.saveServer(serverToSave, workingPath: workingPath)
        }.value

        await MainActor.run {
            if let index = serversByWorkingPath[workingPath]?.firstIndex(where: { $0.id == server.id }) {
                serversByWorkingPath[workingPath]?[index] = server
            } else {
                if serversByWorkingPath[workingPath] == nil {
                    serversByWorkingPath[workingPath] = []
                }
                serversByWorkingPath[workingPath]?.append(server)
            }
        }

        Logger.shared.info("成功更新服务器: \(server.name) (工作路径: \(workingPath))")
    }

    func updateServerSilently(_ server: ServerInstance) -> Bool {
        Task {
            do {
                try await updateServer(server)
            } catch {
                GlobalErrorHandler.shared.handle(error)
            }
        }
        return true
    }

    func updateServerLastPlayed(id: String, lastPlayed: Date = Date()) async throws {
        let workingPath = currentWorkingPath
        guard var server = getServer(by: id) else { return }
        server.lastPlayed = lastPlayed

        let dbPath = AppPaths.gameVersionDatabase.path
        let serverToSave = server

        try await Task.detached(priority: .userInitiated) {
            let db = ServerDatabase(dbPath: dbPath)
            try? db.initialize()
            try db.saveServer(serverToSave, workingPath: workingPath)
        }.value

        let updatedServer = server
        await MainActor.run {
            if let index = serversByWorkingPath[workingPath]?.firstIndex(where: { $0.id == id }) {
                serversByWorkingPath[workingPath]?[index] = updatedServer
            }
        }
    }

    private func loadServersSafely() {
        Task {
            do {
                try await loadServersThrowing()
            } catch {
                GlobalErrorHandler.shared.handle(error)
            }
        }
    }

    func reloadServers() {
        Task {
            do {
                try await loadServersThrowing()
            } catch {
                GlobalErrorHandler.shared.handle(error)
            }
        }
    }

    private func loadServersThrowing() async throws {
        let workingPath = currentWorkingPath
        let dbPath = AppPaths.gameVersionDatabase.path

        let result: [ServerInstance] = try await Task.detached(priority: .userInitiated) {
            let db = ServerDatabase(dbPath: dbPath)
            try? db.initialize()
            var servers = try db.loadServers(workingPath: workingPath)

            // Forge 26+ 在包含非 ASCII 的服务器目录名下会启动失败（Bad escape）。
            // 这里对历史数据做一次迁移：将 Forge 本地服务器目录从 `name` 迁移到 ASCII 安全的 `id`。
            let fileManager = FileManager.default
            var didMigrateAny = false
            for index in servers.indices {
                let server = servers[index]
                guard server.nodeId == ServerNode.local.id else { continue }
                guard server.serverType == .forge else { continue }
                guard server.directoryName == server.name else { continue }
                guard server.name.canBeConverted(to: .ascii) == false else { continue }

                let newDirectoryName = server.id
                let oldDir = AppPaths.serverDirectory(serverName: server.name)
                let newDir = AppPaths.serverDirectory(serverName: newDirectoryName)

                if fileManager.fileExists(atPath: newDir.path) == false,
                   fileManager.fileExists(atPath: oldDir.path) {
                    do {
                        try fileManager.moveItem(at: oldDir, to: newDir)
                        AppPaths.invalidatePaths(forServerName: server.name)
                        AppPaths.invalidatePaths(forServerName: newDirectoryName)
                        didMigrateAny = true
                    } catch {
                        Logger.shared.warning("Forge 服务器目录迁移失败: \(error.localizedDescription)")
                        continue
                    }
                }

                if fileManager.fileExists(atPath: newDir.path) {
                    servers[index].directoryName = newDirectoryName
                    didMigrateAny = true
                }
            }

            if didMigrateAny {
                for server in servers {
                    try? db.saveServer(server, workingPath: workingPath)
                }
            }

            return servers
        }.value

        let (uniqueServers, duplicateIds) = dedupeByNodeAndName(servers: result)

        await MainActor.run {
            serversByWorkingPath[workingPath] = uniqueServers
            ServerStatusManager.shared.reconcileLoadedServers(uniqueServers)
        }

        if !duplicateIds.isEmpty {
            let ids = duplicateIds
            Task.detached(priority: .userInitiated) {
                let db = ServerDatabase(dbPath: dbPath)
                try? db.initialize()
                for id in ids {
                    try? db.deleteServer(id: id)
                }
            }
        }

        Logger.shared.info("加载服务器: \(result.count) (工作路径: \(workingPath))")

        validateServers(workingPath: workingPath)
    }

    private func dedupeByNodeAndName(servers: [ServerInstance]) -> ([ServerInstance], [String]) {
        var latestByKey: [String: ServerInstance] = [:]
        var duplicates: [String] = []

        for server in servers {
            let key = "\(server.nodeId)::\(server.name)"
            if let existing = latestByKey[key] {
                if server.lastPlayed > existing.lastPlayed {
                    latestByKey[key] = server
                    duplicates.append(existing.id)
                } else {
                    duplicates.append(server.id)
                }
            } else {
                latestByKey[key] = server
            }
        }

        let unique = Array(latestByKey.values).sorted { $0.lastPlayed > $1.lastPlayed }
        return (unique, duplicates)
    }

    private func validateServers(workingPath: String) {
        guard let servers = serversByWorkingPath[workingPath] else { return }
        var corrupted: [String] = []

        for server in servers {
            if server.nodeId != ServerNode.local.id {
                continue
            }
            let dir = AppPaths.serverDirectory(serverName: server.directoryName)
            if !FileManager.default.fileExists(atPath: dir.path) {
                corrupted.append(server.name)
            }
        }

        DispatchQueue.main.async {
            self.corruptedServersByWorkingPath[workingPath] = corrupted
        }
    }
}
