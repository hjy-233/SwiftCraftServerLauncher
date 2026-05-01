import Foundation

final class ServerProcessManager: ObservableObject, @unchecked Sendable {
    static let shared = ServerProcessManager()

    private var serverProcesses: [String: Process] = [:]
    private var manuallyStoppedServers: Set<String> = []
    private let queue = DispatchQueue(label: "com.swiftcraftlauncher.serverprocessmanager")

    private init() {}

    func storeProcess(serverId: String, process: Process) {
        process.terminationHandler = { [weak self] process in
            Task { await self?.handleProcessTermination(serverId: serverId, process: process) }
        }

        queue.async { [weak self] in
            self?.serverProcesses[serverId] = process
        }
        Logger.shared.debug("存储服务器进程: \(serverId)")
    }

    private func handleProcessTermination(serverId: String, process: Process) async {
        let wasManuallyStopped = queue.sync { manuallyStoppedServers.contains(serverId) }
        if wasManuallyStopped {
            Logger.shared.debug("服务器被用户主动停止: \(serverId)")
        } else {
            Logger.shared.info("服务器进程已退出: \(serverId)")
        }

        await MainActor.run {
            ServerStatusManager.shared.setServerRunning(serverId: serverId, isRunning: false)
        }
        await MainActor.run {
            ServerConsoleManager.shared.detach(serverId: serverId)
        }

        queue.async { [weak self] in
            self?.serverProcesses.removeValue(forKey: serverId)
            self?.manuallyStoppedServers.remove(serverId)
        }
    }

    func getProcess(for serverId: String) -> Process? {
        queue.sync { serverProcesses[serverId] }
    }

    func stopProcess(for serverId: String) -> Bool {
        let process: Process? = queue.sync {
            guard let proc = serverProcesses[serverId] else { return nil }
            manuallyStoppedServers.insert(serverId)
            return proc
        }

        guard let process else { return false }
        process.terminate()
        return true
    }

    func isServerRunning(serverId: String) -> Bool {
        if let process = getProcess(for: serverId) {
            return process.isRunning
        }
        return false
    }

    func runningProcessCount() -> Int {
        queue.sync { serverProcesses.values.filter(\.isRunning).count }
    }

    func removeServerState(serverId: String) {
        queue.async { [weak self] in
            self?.serverProcesses.removeValue(forKey: serverId)
            self?.manuallyStoppedServers.remove(serverId)
        }
    }
}
