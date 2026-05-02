import Foundation

enum ServerScheduleCoreService {
    static func readSchedules(server: ServerInstance) async throws -> [ServerSchedule] {
        let response: ScslCoreCLIEnvelope<[ServerSchedule]> = try await ScslCoreCLIService.shared.runJSON(
            arguments: ["server", "schedules", "read", server.id]
        )
        return response.data
    }

    static func writeSchedules(server: ServerInstance, schedules: [ServerSchedule]) async throws {
        let data = try JSONEncoder().encode(schedules)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ScslCoreCLIError.invalidUTF8
        }
        let _: ScslCoreCLIEnvelope<EmptyCLIResponse> = try await ScslCoreCLIService.shared.runJSON(
            arguments: ["server", "schedules", "write", server.id],
            standardInput: json
        )
    }
}
