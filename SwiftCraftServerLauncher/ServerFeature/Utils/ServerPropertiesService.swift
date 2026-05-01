import Foundation

enum ServerPropertiesService {
    static func readProperties(server: ServerInstance) async throws -> [String: String] {
        let output = try await ScslCoreCLIService.shared.run(
            arguments: ["server", "properties", "read", server.id]
        )
        let data = Data(output.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let properties = object as? [String: String] else {
            throw ScslCoreCLIError.executionFailed("server.properties 返回格式无效")
        }
        return properties
    }

    static func writeProperties(
        server: ServerInstance,
        properties: [String: String]
    ) async throws {
        let data = try JSONSerialization.data(withJSONObject: properties, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw ScslCoreCLIError.invalidUTF8
        }
        _ = try await ScslCoreCLIService.shared.run(
            arguments: ["server", "properties", "write", server.id, "--json", json]
        )
    }
}
