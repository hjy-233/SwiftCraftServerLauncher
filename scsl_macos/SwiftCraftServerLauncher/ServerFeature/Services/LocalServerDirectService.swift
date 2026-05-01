import Foundation
import Darwin

enum LocalServerDirectService {
    static func start(server: ServerInstance, launchCommand: String) throws {
        let serverDir = AppPaths.serverDirectory(serverName: server.directoryName)
        let escapedServerDir = escapeSingleQuotes(serverDir.path)
        let escapedLaunchCommand = launchCommand.replacingOccurrences(of: "\"", with: "\\\"")
        Logger.shared.info("Local launch command: \(launchCommand)")
        let command = """
        cd '\(escapedServerDir)' && \
        if test -f .scsl.pid && kill -0 $(cat .scsl.pid) 2>/dev/null; then \
          echo __SCSL_ALREADY_RUNNING__; \
        else \
          rm -f .scsl.pid .scsl.stdin; \
          mkfifo .scsl.stdin && \
          nohup /bin/sh -lc "tail -f .scsl.stdin | /bin/sh -lc \\\"\(escapedLaunchCommand)\\\"" >> scsl-server.log 2>&1 & \
          echo $! > .scsl.pid; \
          sleep 1; \
          if test -f .scsl.pid && kill -0 $(cat .scsl.pid) 2>/dev/null; then echo __SCSL_STARTED__; else echo __SCSL_START_FAILED__; fi; \
        fi
        """
        let output = try runLocalShell(command)
        if output.contains("__SCSL_ALREADY_RUNNING__") {
            throw GlobalError.validation(
                chineseMessage: "服务器已在运行",
                i18nKey: "error.validation.server_not_selected",
                level: .notification
            )
        }
        guard output.contains("__SCSL_STARTED__") else {
            throw GlobalError.validation(
                chineseMessage: "本地启动失败，请检查控制台日志",
                i18nKey: "error.validation.server_not_selected",
                level: .notification
            )
        }
    }

    static func stop(server: ServerInstance) throws {
        let serverDir = AppPaths.serverDirectory(serverName: server.directoryName)
        let escapedServerDir = escapeSingleQuotes(serverDir.path)
        let escapedJar = escapeSingleQuotes(server.serverJar)
        let command = """
        cd '\(escapedServerDir)' && \
        if test -f .scsl.pid; then kill $(cat .scsl.pid) 2>/dev/null || true; rm -f .scsl.pid; fi && \
        rm -f .scsl.stdin && \
        pkill -f '\(escapedJar)' || true
        """
        _ = try runLocalShell(command)
    }

    static func sendCommand(server: ServerInstance, command: String) async throws {
        _ = try await ScslCoreCLIService.shared.run(
            arguments: ["server", "send", server.id, command]
        )
    }

    static func sendInterrupt(server: ServerInstance, force: Bool = false) async throws {
        var arguments = ["server", "interrupt", server.id]
        if force {
            arguments.append("--force")
        }
        _ = try await ScslCoreCLIService.shared.run(arguments: arguments)
    }

    static func isDirectModeAvailable(server: ServerInstance) -> Bool {
        let fifo = AppPaths.serverDirectory(serverName: server.directoryName).appendingPathComponent(".scsl.stdin").path
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: fifo, isDirectory: &isDir), !isDir.boolValue {
            return true
        }
        return false
    }

    static func isDirectModeRunning(serverName: String) -> Bool {
        let serverDir = AppPaths.serverDirectory(serverName: serverName)
        let pidURL = serverDir.appendingPathComponent(".scsl.pid")
        guard let pidText = try? String(contentsOf: pidURL) else {
            return false
        }
        let trimmed = pidText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pidValue = Int32(trimmed), pidValue > 0 else {
            return false
        }
        if kill(pidValue, 0) == 0 {
            return true
        }
        let fifoURL = serverDir.appendingPathComponent(".scsl.stdin")
        try? FileManager.default.removeItem(at: pidURL)
        try? FileManager.default.removeItem(at: fifoURL)
        return false
    }

    private static func runLocalShell(_ command: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let out = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw GlobalError.validation(
                chineseMessage: "本地命令执行失败: \((out + err).trimmingCharacters(in: .whitespacesAndNewlines))",
                i18nKey: "error.validation.server_not_selected",
                level: .notification
            )
        }
        return out + err
    }

    private static func escapeSingleQuotes(_ text: String) -> String {
        text.replacingOccurrences(of: "'", with: "'\"'\"'")
    }
}
