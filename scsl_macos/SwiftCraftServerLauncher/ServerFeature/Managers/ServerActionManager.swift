import SwiftUI
import AppKit

@MainActor
class ServerActionManager: ObservableObject {
    static let shared = ServerActionManager()

    private init() {}

    func showInFinder(server: ServerInstance) {
        if server.nodeId != ServerNode.local.id {
            let base = AppPaths.remoteNodeDirectory(nodeId: server.nodeId)
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: base.path)
            Logger.shared.info("在访达中显示远程节点缓存目录: \(base.path)")
            return
        }
        let dir = AppPaths.serverDirectory(serverName: server.directoryName)
        guard FileManager.default.fileExists(atPath: dir.path) else {
            Logger.shared.warning("服务器目录不存在: \(dir.path)")
            return
        }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
        Logger.shared.info("在访达中显示服务器目录: \(server.name)")
    }

    func deleteServer(
        server: ServerInstance,
        serverRepository: ServerRepository,
        serverNodeRepository: ServerNodeRepository,
        selectedItem: Binding<SidebarItem>? = nil
    ) {
        Task {
            do {
                if let selectedItem = selectedItem {
                    await MainActor.run {
                        if let firstServer = serverRepository.servers.first(where: { $0.id != server.id }) {
                            selectedItem.wrappedValue = .server(firstServer.id)
                        } else {
                            selectedItem.wrappedValue = .resource(.browse)
                        }
                    }
                }

                if server.nodeId == ServerNode.local.id {
                    _ = try await ScslCoreCLIService.shared.run(arguments: ["server", "delete", server.id])
                } else {
                    throw GlobalError.validation(
                        chineseMessage: "远程节点功能已停用，请先迁移或导回本地服务器后再删除。",
                        i18nKey: "error.validation.server_not_selected",
                        level: .notification
                    )
                }

                AppPaths.invalidatePaths(forServerName: server.name)
                AppPaths.invalidatePaths(forServerName: server.directoryName)
                ServerProcessManager.shared.removeServerState(serverId: server.id)
                ServerStatusManager.shared.removeServerState(serverId: server.id)
                serverRepository.reloadServers()

                Logger.shared.info("成功删除服务器: \(server.name)")
            } catch {
                let globalError = GlobalError.fileSystem(
                    chineseMessage: "删除服务器失败: \(error.localizedDescription)",
                    i18nKey: "error.filesystem.server_deletion_failed",
                    level: .notification
                )
                Logger.shared.error("删除服务器失败: \(globalError.chineseMessage)")
                GlobalErrorHandler.shared.handle(globalError)
            }
        }
    }

    func deleteCorruptedServer(
        name: String,
        serverRepository: ServerRepository
    ) {
        Task {
            do {
                _ = try await ScslCoreCLIService.shared.run(arguments: ["server", "delete-corrupted", name])
                AppPaths.invalidatePaths(forServerName: name)
                serverRepository.reloadServers()

                Logger.shared.info("成功删除损坏服务器（目录 + 数据库）: \(name)")
            } catch {
                let globalError = GlobalError.fileSystem(
                    chineseMessage: "删除损坏服务器失败: \(error.localizedDescription)",
                    i18nKey: "error.filesystem.server_deletion_failed",
                    level: .notification
                )
                Logger.shared.error("删除损坏服务器失败: \(globalError.chineseMessage)")
                GlobalErrorHandler.shared.handle(globalError)
            }
        }
    }
}
