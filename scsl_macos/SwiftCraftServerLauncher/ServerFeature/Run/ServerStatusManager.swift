import Foundation

class ServerStatusManager: ObservableObject {
    static let shared = ServerStatusManager()
    private static let runningStatesStorageKey = "server.running.states"

    @Published private var serverRunningStates: [String: Bool] = [:]
    @Published private var serverLaunchingStates: [String: Bool] = [:]
    private var serverIdToDirectoryName: [String: String] = [:]
    private var launchStartTimes: [String: Date] = [:]
    private var statusPollTimer: Timer?
    private var pollingServerId: String?

    private init() {
        serverRunningStates = UserDefaults.standard.dictionary(forKey: Self.runningStatesStorageKey) as? [String: Bool] ?? [:]
    }

    func isServerRunning(serverId: String) -> Bool {
        return serverRunningStates[serverId] ?? false
    }

    private func updateServerStatusIfNeeded(serverId: String, actuallyRunning: Bool) {
        if let cachedState = serverRunningStates[serverId], cachedState != actuallyRunning {
            serverRunningStates[serverId] = actuallyRunning
            persistRunningStates()
        } else if serverRunningStates[serverId] == nil {
            serverRunningStates[serverId] = actuallyRunning
            persistRunningStates()
        }
    }

    func setServerRunning(serverId: String, isRunning: Bool) {
        applyOnMain { [weak self] in
            guard let self else { return }
            let currentState = self.serverRunningStates[serverId]
            if currentState != isRunning {
                self.serverRunningStates[serverId] = isRunning
                self.persistRunningStates()
            }
        }
    }

    func startPolling(serverId: String) {
        applyOnMain { [weak self] in
            guard let self else { return }
            if self.pollingServerId == serverId, self.statusPollTimer != nil {
                return
            }
            self.pollingServerId = serverId
            self.statusPollTimer?.invalidate()
            let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.refreshRunningState(serverId: serverId)
            }
            self.statusPollTimer = timer
            RunLoop.main.add(timer, forMode: .common)
            self.refreshRunningState(serverId: serverId)
        }
    }

    func stopPolling() {
        applyOnMain { [weak self] in
            guard let self else { return }
            self.statusPollTimer?.invalidate()
            self.statusPollTimer = nil
            self.pollingServerId = nil
        }
    }

    private func refreshRunningState(serverId: String) {
        let actuallyRunning = ServerProcessManager.shared.isServerRunning(serverId: serverId)
            || isDirectModeRunning(serverId: serverId)
        if shouldSkipFalseUpdate(serverId: serverId, actual: actuallyRunning) {
            return
        }
        updateServerStatusIfNeeded(serverId: serverId, actuallyRunning: actuallyRunning)
    }

    func setServerLaunching(serverId: String, isLaunching: Bool) {
        applyOnMain { [weak self] in
            guard let self else { return }
            let currentState = self.serverLaunchingStates[serverId] ?? false
            if currentState != isLaunching {
                self.serverLaunchingStates[serverId] = isLaunching
                if isLaunching {
                    self.launchStartTimes[serverId] = Date()
                } else {
                    self.launchStartTimes.removeValue(forKey: serverId)
                }
            }
        }
    }

    func isServerLaunching(serverId: String) -> Bool {
        serverLaunchingStates[serverId] ?? false
    }

    func removeServerState(serverId: String) {
        applyOnMain { [weak self] in
            self?.serverRunningStates.removeValue(forKey: serverId)
            self?.serverLaunchingStates.removeValue(forKey: serverId)
            self?.launchStartTimes.removeValue(forKey: serverId)
            self?.serverIdToDirectoryName.removeValue(forKey: serverId)
            self?.persistRunningStates()
        }
    }

    func reconcileLoadedServers(_ servers: [ServerInstance]) {
        applyOnMain { [weak self] in
            guard let self else { return }
            var changed = false
            let localIds = Set(servers.filter { $0.nodeId == ServerNode.local.id }.map(\.id))
            for server in servers where server.nodeId == ServerNode.local.id {
                self.serverIdToDirectoryName[server.id] = server.directoryName
            }
            for server in servers where server.nodeId == ServerNode.local.id {
                let actual = LocalServerDirectService.isDirectModeRunning(serverName: server.directoryName)
                    || ServerProcessManager.shared.isServerRunning(serverId: server.id)
                if self.serverRunningStates[server.id] != actual,
                   shouldSkipFalseUpdate(serverId: server.id, actual: actual) == false {
                    self.serverRunningStates[server.id] = actual
                    changed = true
                }
                if !actual, self.serverLaunchingStates[server.id] == true {
                    self.serverLaunchingStates[server.id] = false
                }
            }
            for id in self.serverRunningStates.keys where localIds.contains(id) == false {
                self.serverRunningStates[id] = false
                changed = true
            }
            for id in self.serverIdToDirectoryName.keys where localIds.contains(id) == false {
                self.serverIdToDirectoryName.removeValue(forKey: id)
            }
            if changed {
                self.persistRunningStates()
            }
        }
    }

    private func persistRunningStates() {
        UserDefaults.standard.set(serverRunningStates, forKey: Self.runningStatesStorageKey)
    }

    private func isDirectModeRunning(serverId: String) -> Bool {
        guard let directoryName = serverIdToDirectoryName[serverId] else {
            return false
        }
        return LocalServerDirectService.isDirectModeRunning(serverName: directoryName)
    }

    private func shouldSkipFalseUpdate(serverId: String, actual: Bool) -> Bool {
        if actual {
            return false
        }
        guard serverLaunchingStates[serverId] == true else {
            return false
        }
        guard let startedAt = launchStartTimes[serverId] else {
            return false
        }
        return Date().timeIntervalSince(startedAt) < 10
    }

    private func applyOnMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.sync {
                action()
            }
        }
    }
}
