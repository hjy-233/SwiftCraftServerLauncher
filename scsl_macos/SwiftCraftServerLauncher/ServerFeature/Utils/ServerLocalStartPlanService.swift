import Foundation

enum ServerLocalStartPlanService {
    static func prepare(server: ServerInstance, javaPath: String) async throws -> LocalStartPlanResponse {
        let response: ScslCoreCLIEnvelope<LocalStartPlanResponse> = try await ScslCoreCLIService.shared.runJSON(
            arguments: ["server", "local-start-plan", server.id, "--java-path", javaPath]
        )
        return response.data
    }
}

struct LocalStartPlanResponse: Decodable {
    let launchCommand: String
    let forgeInstalled: Bool
    let port: Int
    let portAvailable: Bool
    let portProcesses: [LocalStartPlanPortProcess]
}

struct LocalStartPlanPortProcess: Decodable {
    let pid: Int
    let command: String
    let user: String
}
