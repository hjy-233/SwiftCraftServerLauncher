import Foundation

enum ServerPlayerListService {
    struct PlayerEntry: Codable, Hashable {
        var uuid: String
        var name: String
        var level: Int?
        var bypassesPlayerLimit: Bool
        var created: String?
        var source: String?
        var expires: String?
        var reason: String?
        var ip: String?

        enum CodingKeys: String, CodingKey {
            case uuid, name, level, bypassesPlayerLimit, created, source, expires, reason, ip
        }

        init(
            uuid: String,
            name: String,
            level: Int?,
            bypassesPlayerLimit: Bool,
            created: String?,
            source: String?,
            expires: String?,
            reason: String?,
            ip: String?
        ) {
            self.uuid = uuid
            self.name = name
            self.level = level
            self.bypassesPlayerLimit = bypassesPlayerLimit
            self.created = created
            self.source = source
            self.expires = expires
            self.reason = reason
            self.ip = ip
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            uuid = try container.decodeIfPresent(String.self, forKey: .uuid) ?? ""
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            level = try container.decodeIfPresent(Int.self, forKey: .level)
            bypassesPlayerLimit = try container.decodeIfPresent(Bool.self, forKey: .bypassesPlayerLimit) ?? false
            created = try container.decodeIfPresent(String.self, forKey: .created)
            source = try container.decodeIfPresent(String.self, forKey: .source)
            expires = try container.decodeIfPresent(String.self, forKey: .expires)
            reason = try container.decodeIfPresent(String.self, forKey: .reason)
            ip = try container.decodeIfPresent(String.self, forKey: .ip)
        }
    }

    static func readList(serverDir: URL, fileName: String) throws -> [PlayerEntry] {
        let url = serverDir.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode([PlayerEntry].self, from: data)
    }

    static func writeList(serverDir: URL, fileName: String, entries: [PlayerEntry]) throws {
        let url = serverDir.appendingPathComponent(fileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        try data.write(to: url, options: .atomic)
    }
}
