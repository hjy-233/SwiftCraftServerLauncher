import Foundation
import SwiftUI

@MainActor
class ServerSetupUtil: ObservableObject {
    @Published var downloadState = DownloadState()

    func checkServerNameDuplicate(_ name: String) async -> Bool {
        guard !name.isEmpty else { return false }
        let dir = AppPaths.serverRootDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: dir.path)
    }

    func createServerDirectory(name: String) throws -> URL {
        let dir = AppPaths.serverDirectory(serverName: name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func copyCustomJar(from source: URL, to serverDir: URL) throws -> String {
        let target = serverDir.appendingPathComponent(source.lastPathComponent)
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: source, to: target)
        return target.lastPathComponent
    }

    func acceptEula(in serverDir: URL) throws {
        let eulaURL = serverDir.appendingPathComponent("eula.txt")
        let content = "eula=true\n# accepted by SwiftCraftServerLauncher\n"
        try content.data(using: .utf8)?.write(to: eulaURL, options: .atomic)
    }
}
