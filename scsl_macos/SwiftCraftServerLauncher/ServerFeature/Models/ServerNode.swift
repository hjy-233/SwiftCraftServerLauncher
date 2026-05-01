import Foundation

struct ServerNode: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var host: String
    var port: Int
    var username: String
    var remoteRootPath: String
    var isLocal: Bool

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 22,
        username: String,
        remoteRootPath: String,
        isLocal: Bool = false
    ) {
        self.id = id.uuidString
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.remoteRootPath = remoteRootPath
        self.isLocal = isLocal
    }

    static let local = Self(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
        name: "Local Node",
        host: "localhost",
        port: 22,
        username: NSUserName(),
        remoteRootPath: AppPaths.serverRootDirectory.path,
        isLocal: true
    )
}
