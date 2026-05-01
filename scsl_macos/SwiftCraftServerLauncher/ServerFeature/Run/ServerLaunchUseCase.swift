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
            if let remoteNode = await resolveRemoteNodeForLaunch(server: server) {
                await launchRemoteServer(server: server, node: remoteNode)
            } else {
                GlobalErrorHandler.shared.handle(
                    GlobalError.validation(
                        chineseMessage: "未找到远程节点配置，无法启动该服务器",
                        i18nKey: "error.validation.server_not_selected",
                        level: .notification
                    )
                )
            }
            return
        }

        if let remoteNode = await resolveRemoteNodeForLaunch(server: server) {
            await launchRemoteServer(server: server, node: remoteNode)
            return
        }

        let serverDir = AppPaths.serverDirectory(serverName: server.directoryName)
        let jarPath = serverDir.appendingPathComponent(server.serverJar).path
        try? await applyLocalConsoleProperties(server: server)
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

        if server.serverType == .forge {
            do {
                try await ensureForgeReady(server: server, serverDir: serverDir)
            } catch {
                Logger.shared.error("Forge 预处理失败: \(error.localizedDescription)")
                GlobalErrorHandler.shared.handle(error)
                return
            }
        }

        await ensureAvailablePort(server: server, serverDir: serverDir)

        let (launchPath, args) = buildLaunchCommand(
            server: server,
            serverDir: serverDir,
            jarPath: jarPath,
            javaPath: resolvedJavaPath
        )

        do {
            let shellCommand = buildLocalShellCommand(launchPath: launchPath, args: args)
            try LocalServerDirectService.start(server: server, launchCommand: shellCommand)
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
            await stopRemoteServer(server: server)
            return
        }
        await stopLocalServer(server: server)
    }

    @MainActor
    private func launchRemoteServer(server: ServerInstance, node: ServerNode) async {
        let custom = server.launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let launchCommand = custom.isEmpty
            ? buildRemoteDefaultLaunchCommand(serverJar: server.serverJar)
            : appendNoGuiIfNeeded(command: custom)

        do {
            try await SSHNodeService.ensureRemoteJava21(node: node)
            try await SSHNodeService.updateRemoteServerProperties(node: node, server: server)
            try await ensureRemoteAvailablePort(server: server, node: node)
            try await SSHNodeService.startRemoteServer(node: node, server: server, launchCommand: launchCommand)
            ServerStatusManager.shared.setServerRunning(serverId: server.id, isRunning: true)
            ServerConsoleManager.shared.appendSystemMessage(
                serverId: server.id,
                message: "server.console.message.server_started".localized()
            )
        } catch {
            Logger.shared.error("远程服务器启动失败: \(error.localizedDescription)")
            GlobalErrorHandler.shared.handle(error)
            ServerStatusManager.shared.setServerRunning(serverId: server.id, isRunning: false)
            ServerConsoleManager.shared.appendSystemMessage(
                serverId: server.id,
                message: "server.console.message.server_start_failed".localized()
            )
        }
    }

    @MainActor
    private func stopRemoteServer(server: ServerInstance) async {
        guard let node = loadServerNode(nodeId: server.nodeId) else {
            ServerStatusManager.shared.setServerRunning(serverId: server.id, isRunning: false)
            return
        }
        do {
            try await SSHNodeService.stopRemoteServer(node: node, server: server)
        } catch {
            Logger.shared.error("远程服务器停止失败: \(error.localizedDescription)")
            GlobalErrorHandler.shared.handle(error)
        }
        ServerStatusManager.shared.setServerRunning(serverId: server.id, isRunning: false)
        ServerConsoleManager.shared.appendSystemMessage(
            serverId: server.id,
            message: "server.console.message.server_stopped".localized()
        )
    }

    @MainActor
    private func stopLocalServer(server: ServerInstance) async {
        let hasProcess = ServerProcessManager.shared.getProcess(for: server.id) != nil
        let canDirect = LocalServerDirectService.isDirectModeAvailable(server: server)
        if hasProcess || canDirect {
            _ = try? await Task.detached(priority: .userInitiated) {
                try await LocalServerDirectService.sendCommand(server: server, command: "stop")
            }.value
            // wait for graceful shutdown (up to 8s)
            for _ in 0..<16 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if ServerProcessManager.shared.isServerRunning(serverId: server.id) == false,
                   LocalServerDirectService.isDirectModeAvailable(server: server) == false {
                    ServerStatusManager.shared.setServerRunning(serverId: server.id, isRunning: false)
                    ServerConsoleManager.shared.detach(serverId: server.id)
                    return
                }
            }
        }
        _ = try? await Task.detached(priority: .userInitiated) {
            try LocalServerDirectService.stop(server: server)
        }.value
        _ = ServerProcessManager.shared.stopProcess(for: server.id)
        ServerStatusManager.shared.setServerRunning(serverId: server.id, isRunning: false)
        ServerConsoleManager.shared.detach(serverId: server.id)
        ServerConsoleManager.shared.appendSystemMessage(
            serverId: server.id,
            message: "server.console.message.server_stopped".localized()
        )
    }

    private func buildLaunchCommand(
        server: ServerInstance,
        serverDir: URL,
        jarPath: String,
        javaPath: String
    ) -> (String, [String]) {
        let custom = server.launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            let command = normalizeCustomLaunchCommand(
                appendNoGuiIfNeeded(command: custom),
                javaPath: javaPath
            )
            return ("/bin/zsh", ["-lc", command])
        }

        let resolvedJavaPath = javaPath.isEmpty ? "java" : javaPath
        var args: [String] = []

        if server.xms > 0 { args.append("-Xms\(server.xms)M") }
        if server.xmx > 0 { args.append("-Xmx\(server.xmx)M") }
        if !server.jvmArguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args.append(contentsOf: splitArgs(server.jvmArguments))
        }

        if server.serverType == .forge,
            let forgeCommand = buildForgeLaunchCommand(
                serverDir: serverDir,
                resolvedJavaPath: resolvedJavaPath
            ) {
            if forgeCommand.launchPath == "/bin/zsh" {
                return (forgeCommand.launchPath, forgeCommand.args)
            }
            let forgeArgs = args + forgeCommand.args
            return (forgeCommand.launchPath, forgeArgs)
        }

        args.append(contentsOf: ["-jar", jarPath, "nogui"])

        return (resolvedJavaPath, args)
    }

    private func ensureForgeReady(server: ServerInstance, serverDir: URL) async throws {
        if ForgeInstallerService.hasLaunchArtifacts(in: serverDir) {
            return
        }
        guard ForgeInstallerService.isInstallerJar(server.serverJar) else {
            return
        }
        try await ForgeInstallerService.install(server: server, serverDir: serverDir)
    }

    private func buildLocalShellCommand(launchPath: String, args: [String]) -> String {
        if launchPath == "/bin/zsh", args.count >= 2, args[0] == "-lc" {
            return args[1]
        }
        let escaped = ([launchPath] + args).map { value in
            "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
        }
        return escaped.joined(separator: " ")
    }

    private func buildForgeLaunchCommand(
        serverDir: URL,
        resolvedJavaPath: String
    ) -> (launchPath: String, args: [String])? {
        let runScript = serverDir.appendingPathComponent("run.sh")
        if FileManager.default.fileExists(atPath: runScript.path) {
            let javaHome = URL(fileURLWithPath: resolvedJavaPath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .path
            let escapedJavaHome = javaHome.replacingOccurrences(of: "'", with: "'\"'\"'")
            // Forge 的 run.sh 会优先使用 JAVA_HOME/bin/java；这里强制它走我们解析出来的运行时，
            // 避免继续使用系统自带 Java（例如 24）导致 Forge 需要 Java 25+ 时启动失败。
            return ("/bin/zsh", ["-lc", "env JAVA_HOME='\(escapedJavaHome)' ./run.sh nogui"])
        }

        if let unixArgs = ForgeInstallerService.findUnixArgsFile(in: serverDir) {
            return (resolvedJavaPath, ["@\(unixArgs.path)", "nogui"])
        }

        if let forgeServerJar = ForgeInstallerService.findForgeServerJar(in: serverDir) {
            return (resolvedJavaPath, ["-jar", forgeServerJar.path, "nogui"])
        }

        return nil
    }

    private func ensureAvailablePort(server: ServerInstance, serverDir: URL) async {
        do {
            let propertiesURL = serverDir.appendingPathComponent("server.properties")
            guard FileManager.default.fileExists(atPath: propertiesURL.path) else { return }
            let properties = try await ServerPropertiesService.readProperties(server: server)
            let portString = properties["server-port"] ?? "25565"
            let port = Int(portString) ?? 25565
            if ServerPortChecker.isPortAvailable(port) {
                return
            }
            let processes = ServerPortChecker.localPortProcesses(port)
            let shouldKill = await promptPortConflict(
                title: "本地端口被占用",
                port: port,
                details: processes.map { "PID \($0.pid)  \($0.user)  \($0.command)" }
            )
            if shouldKill {
                for process in processes {
                    _ = ServerPortChecker.killLocalProcess(pid: process.pid)
                }
            }
        } catch {
            GlobalErrorHandler.shared.handle(error)
        }
    }

    private func ensureRemoteAvailablePort(server: ServerInstance, node: ServerNode) async throws {
        let properties = try await SSHNodeService.readRemoteServerProperties(node: node, serverName: server.name)
        let port = Int(properties["server-port"] ?? "25565") ?? 25565
        let processes = try await SSHNodeService.remotePortProcesses(node: node, port: port)
        if processes.isEmpty {
            return
        }
        let shouldKill = await promptPortConflict(
            title: "远程端口被占用",
            port: port,
            details: processes.map { "PID \($0.pid)  \($0.user)  \($0.command)" }
        )
        if shouldKill {
            for process in processes {
                try await SSHNodeService.killRemoteProcess(node: node, pid: process.pid)
            }
        }
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

    private func loadServerNode(nodeId: String) -> ServerNode? {
        let url = AppPaths.dataDirectory.appendingPathComponent("server_nodes.json")
        guard
            let data = try? Data(contentsOf: url),
            let nodes = try? JSONDecoder().decode([ServerNode].self, from: data)
        else { return nil }
        return nodes.first { $0.id == nodeId }
    }

    @MainActor
    private func resolveRemoteNodeForLaunch(server: ServerInstance) async -> ServerNode? {
        if server.nodeId != ServerNode.local.id, let node = loadServerNode(nodeId: server.nodeId) {
            return node
        }

        let localJar = AppPaths.serverDirectory(serverName: server.directoryName).appendingPathComponent(server.serverJar)
        if FileManager.default.fileExists(atPath: localJar.path) {
            return nil
        }

        guard server.javaPath == "java" else {
            return nil
        }

        let url = AppPaths.dataDirectory.appendingPathComponent("server_nodes.json")
        guard
            let data = try? Data(contentsOf: url),
            let nodes = try? JSONDecoder().decode([ServerNode].self, from: data)
        else {
            return nil
        }
        let remoteNodes = nodes.filter { !$0.isLocal }
        for node in remoteNodes where (try? await SSHNodeService.remoteServerDirectoryExists(node: node, serverName: server.name)) == true {
            return node
        }
        return nil
    }

    private func appendNoGuiIfNeeded(command: String) -> String {
        let tokens = splitArgs(command)
        if tokens.contains("nogui") {
            return command
        }
        return command + " nogui"
    }

    private func splitArgs(_ input: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var quoteChar: Character = "\""

        for char in input {
            if char == "\"" || char == "'" {
                if inQuotes && char == quoteChar {
                    inQuotes = false
                } else if !inQuotes {
                    inQuotes = true
                    quoteChar = char
                } else {
                    current.append(char)
                }
                continue
            }

            if char == " " && !inQuotes {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    private func normalizeCustomLaunchCommand(_ command: String, javaPath: String) -> String {
        let trimmedJavaPath = javaPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmedJavaPath.isEmpty,
            trimmedJavaPath.contains(" "),
            command.hasPrefix(trimmedJavaPath)
        else {
            return command
        }

        let escapedJavaPath = trimmedJavaPath.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escapedJavaPath)'" + command.dropFirst(trimmedJavaPath.count)
    }

    private func buildRemoteDefaultLaunchCommand(serverJar: String) -> String {
        """
        JAVA_BIN=""
        if command -v java21 >/dev/null 2>&1; then
          JAVA_BIN="$(command -v java21)"
        elif command -v java >/dev/null 2>&1; then
          JAVA_MAJOR="$(java -version 2>&1 | sed -n 's/.*version \"\\([0-9][0-9]*\\).*/\\1/p' | head -n 1)"
          if [ -n "$JAVA_MAJOR" ] && [ "$JAVA_MAJOR" -ge 21 ]; then
            JAVA_BIN="$(command -v java)"
          fi
        fi
        if [ -z "$JAVA_BIN" ]; then
          echo "ERROR: Java 21+ is required for this server."
          exit 1
        fi
        "$JAVA_BIN" -jar '\(serverJar)' nogui
        """
    }

    private func applyLocalConsoleProperties(server: ServerInstance) async throws {
        var properties = try await ServerPropertiesService.readProperties(server: server)
        properties["enable-rcon"] = "false"
        properties["rcon.port"] = String(server.rconPort)
        if !server.rconPassword.isEmpty {
            properties["rcon.password"] = server.rconPassword
        }
        try await ServerPropertiesService.writeProperties(server: server, properties: properties)
    }
}
