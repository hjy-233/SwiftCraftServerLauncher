import Foundation

struct MirrorCustomAPIConfig: Codable, Hashable {
    var schemaVersion: Int
    var baseURL: String
    var unwrapData: Bool
    var coreListPath: String
    var coreDetailPath: String
    var coreBuildsPath: String
    var coreBuildDetailPath: String
    var coresKeyPath: String
    var coreNameKey: String
    var coreTagKey: String
    var coreRecommendKey: String
    var versionsKeyPath: String
    var buildsKeyPath: String
    var buildVersionKey: String
    var buildSha1Key: String
    var buildUpdateKey: String
    var buildDownloadURLKey: String
    var buildFileNameKey: String

    static let currentSchemaVersion = 1

    static var defaultConfig: Self {
        Self(
            schemaVersion: Self.currentSchemaVersion,
            baseURL: "https://",
            unwrapData: true,
            coreListPath: "/api/v3",
            coreDetailPath: "/api/v3/{core}",
            coreBuildsPath: "/api/v3/{core}/{mc_version}",
            coreBuildDetailPath: "/api/v3/{core}/{mc_version}/{core_version}",
            coresKeyPath: "",
            coreNameKey: "name",
            coreTagKey: "tag",
            coreRecommendKey: "recommend",
            versionsKeyPath: "mc_versions",
            buildsKeyPath: "builds",
            buildVersionKey: "core_version",
            buildSha1Key: "sha1",
            buildUpdateKey: "update_time",
            buildDownloadURLKey: "download_url",
            buildFileNameKey: "filename"
        )
    }

    static var defaultJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(Self.defaultConfig),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}
