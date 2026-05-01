import Foundation

enum ServerConsoleMode: String, Codable, CaseIterable, Identifiable {
    case rcon
    case direct

    var id: String { rawValue }
}

enum ServerType: String, Codable, CaseIterable, Identifiable {
    case vanilla
    case fabric
    case forge
    case paper
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vanilla: return "Vanilla"
        case .fabric: return "Fabric"
        case .forge: return "Forge"
        case .paper: return "Paper"
        case .custom: return "Custom Jar"
        }
    }
}

struct ServerInstance: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    /// Filesystem directory name for this server (local node only).
    /// Defaults to `name` for legacy servers; Forge may require an ASCII-safe name.
    var directoryName: String
    let iconName: String
    let iconImageFileName: String?
    let serverType: ServerType
    let gameVersion: String
    let loaderVersion: String
    let serverJar: String
    var launchCommand: String
    var lastPlayed: Date
    var javaPath: String
    var jvmArguments: String
    var xms: Int
    var xmx: Int
    var nodeId: String
    var consoleMode: ServerConsoleMode
    var rconPort: Int
    var rconPassword: String

    init(
        id: UUID = UUID(),
        name: String,
        directoryName: String? = nil,
        iconName: String = "server.rack",
        iconImageFileName: String? = nil,
        serverType: ServerType,
        gameVersion: String,
        loaderVersion: String = "",
        serverJar: String,
        launchCommand: String = "",
        lastPlayed: Date = Date(),
        javaPath: String = "",
        jvmArguments: String = "",
        xms: Int = 0,
        xmx: Int = 0,
        nodeId: String = ServerNode.local.id,
        consoleMode: ServerConsoleMode = .rcon,
        rconPort: Int = 25575,
        rconPassword: String = ""
    ) {
        self.id = id.uuidString
        self.name = name
        self.directoryName = directoryName ?? name
        self.iconName = iconName
        self.iconImageFileName = iconImageFileName
        self.serverType = serverType
        self.gameVersion = gameVersion
        self.loaderVersion = loaderVersion
        self.serverJar = serverJar
        self.launchCommand = launchCommand
        self.lastPlayed = lastPlayed
        self.javaPath = javaPath
        self.jvmArguments = jvmArguments
        self.xms = xms
        self.xmx = xmx
        self.nodeId = nodeId
        self.consoleMode = consoleMode
        self.rconPort = rconPort
        self.rconPassword = rconPassword
    }

    enum CodingKeys: String, CodingKey {
        case id, name, directoryName, iconName, iconImageFileName, serverType, gameVersion, loaderVersion, serverJar
        case launchCommand, lastPlayed, javaPath, jvmArguments, xms, xmx, nodeId, consoleMode, rconPort, rconPassword
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        directoryName = try container.decodeIfPresent(String.self, forKey: .directoryName) ?? name
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? "server.rack"
        iconImageFileName = try container.decodeIfPresent(String.self, forKey: .iconImageFileName)
        serverType = try container.decode(ServerType.self, forKey: .serverType)
        gameVersion = try container.decode(String.self, forKey: .gameVersion)
        loaderVersion = try container.decodeIfPresent(String.self, forKey: .loaderVersion) ?? ""
        serverJar = try container.decode(String.self, forKey: .serverJar)
        launchCommand = try container.decodeIfPresent(String.self, forKey: .launchCommand) ?? ""
        lastPlayed = try container.decodeIfPresent(Date.self, forKey: .lastPlayed) ?? Date()
        javaPath = try container.decodeIfPresent(String.self, forKey: .javaPath) ?? ""
        jvmArguments = try container.decodeIfPresent(String.self, forKey: .jvmArguments) ?? ""
        xms = try container.decodeIfPresent(Int.self, forKey: .xms) ?? 0
        xmx = try container.decodeIfPresent(Int.self, forKey: .xmx) ?? 0
        nodeId = try container.decodeIfPresent(String.self, forKey: .nodeId) ?? ServerNode.local.id
        consoleMode = try container.decodeIfPresent(ServerConsoleMode.self, forKey: .consoleMode) ?? .rcon
        rconPort = try container.decodeIfPresent(Int.self, forKey: .rconPort) ?? 25575
        rconPassword = try container.decodeIfPresent(String.self, forKey: .rconPassword) ?? ""
    }

    var resolvedIconName: String {
        iconName.isEmpty ? "server.rack" : iconName
    }

    var iconFileURL: URL? {
        let baseDirectory: URL = nodeId == ServerNode.local.id
            ? AppPaths.serverDirectory(serverName: directoryName)
            : AppPaths.remoteNodeServersDirectory(nodeId: nodeId).appendingPathComponent(name, isDirectory: true)
        if let iconImageFileName, !iconImageFileName.isEmpty {
            let specificPath = baseDirectory.appendingPathComponent(iconImageFileName)
            if FileManager.default.fileExists(atPath: specificPath.path) {
                return specificPath
            }
        }
        if let files = try? FileManager.default.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil,
            options: []
        ),
        let matched = files.first(where: { $0.lastPathComponent.hasPrefix(".scsl-server-icon.") }) {
            return matched
        }
        return nil
    }
}
