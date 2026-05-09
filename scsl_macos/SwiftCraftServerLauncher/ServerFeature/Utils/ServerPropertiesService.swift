import Foundation

enum ServerPropertiesService {
    static func readProperties(server: ServerInstance) async throws -> [String: String] {
        let response: ScslCoreCLIEnvelope<[String: String]> = try await ScslCoreCLIService.shared.runJSON(
            arguments: ["server", "properties", "read", server.id]
        )
        return response.data
    }

    static func writeProperties(
        server: ServerInstance,
        properties: [String: String]
    ) async throws {
        let data = try JSONSerialization.data(withJSONObject: properties, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw ScslCoreCLIError.invalidUTF8
        }
        let _: ScslCoreCLIEnvelope<EmptyCLIResponse> = try await ScslCoreCLIService.shared.runJSON(
            arguments: ["server", "properties", "write", server.id, "--json", json]
        )
    }
}
