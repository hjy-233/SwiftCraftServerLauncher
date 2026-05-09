import Foundation

enum GameLaunchCoreService {
    static func buildLaunchPlan(
        game: GameVersionInfo,
        player: Player?
    ) async throws -> GameLaunchPlanResponse {
        let request = GameLaunchPlanRequest(
            javaPath: game.javaPath,
            launchCommand: game.launchCommand,
            xms: game.xms > 0 ? game.xms : GameSettingsManager.shared.globalXms,
            xmx: game.xmx > 0 ? game.xmx : GameSettingsManager.shared.globalXmx,
            jvmArguments: game.jvmArguments,
            workingDirectory: AppPaths.profileDirectory(gameName: game.gameName).path,
            environmentVariables: game.environmentVariables,
            player: player.map(GameLaunchPlayerRequest.init)
        )
        let data = try JSONEncoder().encode(request)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ScslCoreCLIError.invalidUTF8
        }
        let response: ScslCoreCLIEnvelope<GameLaunchPlanResponse> = try await ScslCoreCLIService.shared.runJSON(
            arguments: ["game", "launch-plan", "--json", json]
        )
        return response.data
    }
}

private struct GameLaunchPlanRequest: Encodable {
    let javaPath: String
    let launchCommand: [String]
    let xms: Int
    let xmx: Int
    let jvmArguments: String
    let workingDirectory: String
    let environmentVariables: String
    let player: GameLaunchPlayerRequest?
}

private struct GameLaunchPlayerRequest: Encodable {
    let id: String
    let name: String
    let accessToken: String
    let xuid: String

    init(player: Player) {
        self.id = player.id
        self.name = player.name
        self.accessToken = player.authAccessToken
        self.xuid = player.authXuid
    }
}

struct GameLaunchPlanResponse: Decodable {
    let javaPath: String
    let arguments: [String]
    let workingDirectory: String
    let environment: [String: String]
}
