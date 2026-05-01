import Foundation

enum ServerScheduleCoreService {
    static func readSchedules(server: ServerInstance) async throws -> [ServerSchedule] {
        let output = try await ScslCoreCLIService.shared.run(arguments: ["server", "schedules", "read", server.id])
        let data = Data(output.utf8)
        return try JSONDecoder().decode([ServerSchedule].self, from: data)
    }

    static func writeSchedules(server: ServerInstance, schedules: [ServerSchedule]) async throws {
        let data = try JSONEncoder().encode(schedules)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ScslCoreCLIError.invalidUTF8
        }
        _ = try await ScslCoreCLIService.shared.run(
            arguments: ["server", "schedules", "write", server.id],
            standardInput: json
        )
    }
}
