import Foundation

enum ForgeInstallerService {
    static func install(
        server: ServerInstance,
        serverDir: URL
    ) async throws {
        let jarURL = serverDir.appendingPathComponent(server.serverJar)
        guard FileManager.default.fileExists(atPath: jarURL.path) else {
            throw GlobalError.fileSystem(
                chineseMessage: "找不到 Forge installer: \(jarURL.lastPathComponent)",
                i18nKey: "error.filesystem.file_not_found",
                level: .notification
            )
        }

        let javaPath: String = {
            if !server.javaPath.isEmpty { return server.javaPath }
            return "java"
        }()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: javaPath)
        process.arguments = ["-jar", jarURL.path, "--installServer"]
        process.currentDirectoryURL = serverDir

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        await MainActor.run {
            ServerConsoleManager.shared.attach(serverId: server.id, input: Pipe(), output: outputPipe, error: errorPipe)
        }

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw GlobalError.download(
                chineseMessage: "Forge 安装失败",
                i18nKey: "error.download.general_failure",
                level: .notification
            )
        }
    }

    static func isInstallerJar(_ jarName: String) -> Bool {
        jarName.lowercased().contains("installer")
    }

    static func hasLaunchArtifacts(in serverDir: URL) -> Bool {
        if FileManager.default.fileExists(atPath: serverDir.appendingPathComponent("run.sh").path) {
            return true
        }
        if findUnixArgsFile(in: serverDir) != nil {
            return true
        }
        if findForgeServerJar(in: serverDir) != nil {
            return true
        }
        return false
    }

    static func findUnixArgsFile(in serverDir: URL) -> URL? {
        let libraries = serverDir.appendingPathComponent("libraries")
        guard FileManager.default.fileExists(atPath: libraries.path) else { return nil }
        let enumerator = FileManager.default.enumerator(
            at: libraries,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.lastPathComponent == "unix_args.txt" else { continue }
            if fileURL.path.contains("/net/minecraftforge/forge/") {
                return fileURL
            }
        }
        return nil
    }

    static func findForgeServerJar(in serverDir: URL) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: serverDir,
            includingPropertiesForKeys: nil
        )) ?? []
        return files.first {
            let name = $0.lastPathComponent.lowercased()
            return name.hasPrefix("forge-") && name.hasSuffix("-server.jar")
        }
    }
}
