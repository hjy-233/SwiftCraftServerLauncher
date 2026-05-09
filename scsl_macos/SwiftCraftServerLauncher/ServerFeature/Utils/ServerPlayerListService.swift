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

    static func readList(server: ServerInstance, fileName: String) async throws -> [PlayerEntry] {
        let response: ScslCoreCLIEnvelope<[PlayerEntry]> = try await ScslCoreCLIService.shared.runJSON(
            arguments: ["server", "players", "read", server.id, "--file-name", fileName]
        )
        return response.data
    }

    static func writeList(server: ServerInstance, fileName: String, entries: [PlayerEntry]) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        guard let content = String(data: data, encoding: .utf8) else {
            throw GlobalError.fileSystem(
                chineseMessage: "玩家列表编码失败",
                i18nKey: "error.filesystem.write_failed",
                level: .notification
            )
        }
        let _: ScslCoreCLIEnvelope<EmptyCLIResponse> = try await ScslCoreCLIService.shared.runJSON(
            arguments: ["server", "players", "write", server.id, "--file-name", fileName],
            standardInput: content
        )
    }
}
