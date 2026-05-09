import Foundation
import AppKit

final class ServerLaunchUseCase: ObservableObject {
    @MainActor
    func launchServer(server: ServerInstance) async {
        ServerConsoleManager.shared.appendSystemMessage(
            serverId: server.id,
            message: "server.console.message.server_starting".localized()
        )
        if server.nodeId != ServerNode.local.id {
            handleRemoteNodeUnsupported()
            return
        }

        var resolvedJavaPath = server.javaPath
        if let javaVersion = try? await ServerDownloadService.resolveJavaVersion(gameVersion: server.gameVersion) {
            let needsResolve = resolvedJavaPath.isEmpty
                || resolvedJavaPath == "java"
                || JavaManager.shared.satisfiesMinimumMajorVersion(
                    at: resolvedJavaPath,
                    minimumMajorVersion: javaVersion.majorVersion
                ) == false
            if needsResolve {
                resolvedJavaPath = await JavaManager.shared.ensureJavaExists(
                    version: javaVersion.component,
                    minimumMajorVersion: javaVersion.majorVersion
                )
            }
        }
        if resolvedJavaPath.isEmpty {
            GlobalErrorHandler.shared.handle(
                GlobalError.validation(
                    chineseMessage: "未找到可用的 Java 运行时，请在运行设置中选择 Java，或检查网络后重试。",
                    i18nKey: "error.validation.server_not_selected",
                    level: .notification
                )
            )
            return
        }

        do {
            let plan = try await ServerLocalStartPlanService.prepare(server: server, javaPath: resolvedJavaPath)
            if plan.portAvailable == false {
                let shouldKill = await promptPortConflict(
                    title: "本地端口被占用",
                    port: plan.port,
                    details: plan.portProcesses.map { "PID \($0.pid)  \($0.user)  \($0.command)" }
                )
                if shouldKill {
                    for process in plan.portProcesses {
                        _ = ServerPortChecker.killLocalProcess(pid: process.pid)
                    }
                }
            }
            try await LocalServerDirectService.start(server: server, javaPath: resolvedJavaPath)
            ServerStatusManager.shared.setServerRunning(serverId: server.id, isRunning: true)
            ServerConsoleManager.shared.appendSystemMessage(
                serverId: server.id,
                message: "server.console.message.server_started".localized()
            )
        } catch {
            Logger.shared.error("服务器启动失败: \(error.localizedDescription)")
            GlobalErrorHandler.shared.handle(error)
            ServerConsoleManager.shared.appendSystemMessage(
                serverId: server.id,
                message: "server.console.message.server_start_failed".localized()
            )
        }
    }

    @MainActor
    func stopServer(server: ServerInstance) async {
        if server.nodeId != ServerNode.local.id {
            handleRemoteNodeUnsupported()
            return
        }
        await stopLocalServer(server: server)
    }

    @MainActor
    private func stopLocalServer(server: ServerInstance) async {
        let canDirect = LocalServerDirectService.isDirectModeAvailable(server: server)
        if canDirect || ServerProcessManager.shared.getProcess(for: server.id) != nil {
            _ = try? await Task.detached(priority: .userInitiated) {
                try await LocalServerDirectService.stop(server: server)
            }.value
        }
        _ = ServerProcessManager.shared.stopProcess(for: server.id)
        ServerStatusManager.shared.setServerRunning(serverId: server.id, isRunning: false)
        ServerConsoleManager.shared.detach(serverId: server.id)
        ServerConsoleManager.shared.appendSystemMessage(
            serverId: server.id,
            message: "server.console.message.server_stopped".localized()
        )
    }

    @MainActor
    private func promptPortConflict(title: String, port: Int, details: [String]) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        let body = details.isEmpty ? "端口 \(port) 已被占用" : "端口 \(port) 已被占用\n" + details.joined(separator: "\n")
        alert.informativeText = body
        alert.alertStyle = .warning
        alert.addButton(withTitle: "结束进程")
        alert.addButton(withTitle: "忽略")
        return alert.runModal() == .alertFirstButtonReturn
    }

    @MainActor
    private func handleRemoteNodeUnsupported() {
        GlobalErrorHandler.shared.handle(
            GlobalError.validation(
                chineseMessage: "远程节点功能已停用，请先迁移或导回本地服务器后再操作。",
                i18nKey: "error.validation.server_not_selected",
                level: .notification
            )
        )
    }
}
