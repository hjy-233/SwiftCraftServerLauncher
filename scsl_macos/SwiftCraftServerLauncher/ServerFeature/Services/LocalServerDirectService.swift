import Foundation
import Darwin

enum LocalServerDirectService {
    static func start(server: ServerInstance, javaPath: String) async throws {
        let _: ScslCoreCLIEnvelope<EmptyCLIResponse> = try await ScslCoreCLIService.shared.runJSON(
            arguments: ["server", "local-start", server.id, "--java-path", javaPath]
        )
    }

    static func stop(server: ServerInstance) async throws {
        let _: ScslCoreCLIEnvelope<EmptyCLIResponse> = try await ScslCoreCLIService.shared.runJSON(
            arguments: ["server", "stop", server.id]
        )
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
}
