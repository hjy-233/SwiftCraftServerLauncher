import Foundation

enum CustomMirrorService {
    struct CoreDetail: Hashable {
        let downloadURL: String
        let filename: String
        let sha1: String?
    }

    static func fetchCores(
        config: MirrorCustomAPIConfig,
        baseURL: URL
    ) async throws -> [FastMirrorService.CoreSummary] {
        let url = try buildURL(baseURL: baseURL, template: config.coreListPath)
        let payload = try await fetchPayload(url: url, config: config)
        let root = resolvedRoot(from: payload, config: config)
        let coresValue = resolveValue(for: config.coresKeyPath, in: root) ?? root
        guard let coreArray = coresValue as? [Any] else {
            throw invalidFormatError()
        }
        return coreArray.compactMap { item in
            guard let dict = item as? [String: Any] else { return nil }
            let name = stringValue(in: dict, key: config.coreNameKey)
            guard !name.isEmpty else { return nil }
            let tag = stringValue(in: dict, key: config.coreTagKey)
            let recommend = boolValue(in: dict, key: config.coreRecommendKey)
            return FastMirrorService.CoreSummary(
                name: name,
                tag: tag.isEmpty ? nil : tag,
                recommend: recommend,
                homepage: nil,
                mcVersions: nil
            )
        }
    }

    static func fetchGameVersions(
        config: MirrorCustomAPIConfig,
        baseURL: URL,
        coreName: String
    ) async throws -> [String] {
        let url = try buildURL(
            baseURL: baseURL,
            template: config.coreDetailPath,
            core: coreName
        )
        let payload = try await fetchPayload(url: url, config: config)
        let root = resolvedRoot(from: payload, config: config)
        guard let versionsValue = resolveValue(for: config.versionsKeyPath, in: root) else {
            throw invalidFormatError()
        }
        return normalizeStringArray(versionsValue)
    }

    static func fetchCoreVersions(
        config: MirrorCustomAPIConfig,
        baseURL: URL,
        coreName: String,
        gameVersion: String
    ) async throws -> [String] {
        let url = try buildURL(
            baseURL: baseURL,
            template: config.coreBuildsPath,
            core: coreName,
            mcVersion: gameVersion
        )
        let payload = try await fetchPayload(url: url, config: config)
        let root = resolvedRoot(from: payload, config: config)
        guard let buildsValue = resolveValue(for: config.buildsKeyPath, in: root),
              let buildsArray = buildsValue as? [Any] else {
            throw invalidFormatError()
        }
        let versions = buildsArray.compactMap { item -> String? in
            guard let dict = item as? [String: Any] else { return nil }
            let version = stringValue(in: dict, key: config.buildVersionKey)
            return version.isEmpty ? nil : version
        }
        return uniqueStrings(versions)
    }

    static func fetchCoreDetail(
        config: MirrorCustomAPIConfig,
        baseURL: URL,
        coreName: String,
        gameVersion: String,
        coreVersion: String
    ) async throws -> CoreDetail {
        let url = try buildURL(
            baseURL: baseURL,
            template: config.coreBuildDetailPath,
            core: coreName,
            mcVersion: gameVersion,
            coreVersion: coreVersion
        )
        let payload = try await fetchPayload(url: url, config: config)
        let root = resolvedRoot(from: payload, config: config)
        let downloadURL = stringValue(in: root, key: config.buildDownloadURLKey)
        let filename = stringValue(in: root, key: config.buildFileNameKey)
        let sha1 = stringValue(in: root, key: config.buildSha1Key)
        guard !downloadURL.isEmpty, !filename.isEmpty else {
            throw invalidFormatError()
        }
        return CoreDetail(
            downloadURL: downloadURL,
            filename: filename,
            sha1: sha1.isEmpty ? nil : sha1
        )
    }

    private static func fetchPayload(url: URL, config: MirrorCustomAPIConfig) async throws -> Any {
        let data = try await APIClient.get(url: url, headers: ["Accept": "application/json"])
        guard let payload = try? JSONSerialization.jsonObject(with: data) else {
            throw invalidFormatError()
        }
        return payload
    }

    private static func resolvedRoot(from payload: Any, config: MirrorCustomAPIConfig) -> Any {
        if config.unwrapData,
           let dict = payload as? [String: Any],
           let data = dict["data"] {
            return data
        }
        return payload
    }

    private static func resolveValue(for keyPath: String, in root: Any) -> Any? {
        guard !keyPath.isEmpty else { return root }
        let components = keyPath.split(separator: ".").map(String.init)
        var current: Any? = root
        for component in components {
            if let index = Int(component), let array = current as? [Any], array.indices.contains(index) {
                current = array[index]
                continue
            }
            guard let dict = current as? [String: Any] else { return nil }
            current = dict[component]
        }
        return current
    }

    private static func buildURL(
        baseURL: URL,
        template: String,
        core: String = "",
        mcVersion: String = "",
        coreVersion: String = ""
    ) throws -> URL {
        var resolved = template
        resolved = resolved.replacingOccurrences(of: "{core}", with: core)
        resolved = resolved.replacingOccurrences(of: "{mc_version}", with: mcVersion)
        resolved = resolved.replacingOccurrences(of: "{core_version}", with: coreVersion)
        if resolved.lowercased().hasPrefix("http"),
           let url = URL(string: resolved) {
            return url
        }
        let trimmedPath = resolved.hasPrefix("/") ? String(resolved.dropFirst()) : resolved
        guard !trimmedPath.isEmpty else {
            throw invalidFormatError()
        }
        return baseURL.appendingPathComponent(trimmedPath)
    }

    private static func stringValue(in dict: [String: Any], key: String) -> String {
        if let value = dict[key] as? String {
            return value
        }
        if let number = dict[key] as? NSNumber {
            return number.stringValue
        }
        return ""
    }

    private static func stringValue(in root: Any, key: String) -> String {
        guard let dict = root as? [String: Any] else { return "" }
        return stringValue(in: dict, key: key)
    }

    private static func boolValue(in dict: [String: Any], key: String) -> Bool {
        if let value = dict[key] as? Bool {
            return value
        }
        if let number = dict[key] as? NSNumber {
            return number.boolValue
        }
        return false
    }

    private static func normalizeStringArray(_ value: Any) -> [String] {
        if let array = value as? [String] {
            return array
        }
        if let array = value as? [Any] {
            return array.compactMap { item in
                if let str = item as? String { return str }
                if let num = item as? NSNumber { return num.stringValue }
                return nil
            }
        }
        return []
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var unique: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            unique.append(value)
        }
        return unique
    }

    private static func invalidFormatError() -> Error {
        GlobalError.network(
            chineseMessage: "镜像服务数据格式不正确",
            i18nKey: "error.network.api_request_failed",
            level: .notification
        )
    }
}
