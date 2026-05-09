import Foundation

/// 服务器地址服务
/// 负责读取和管理 Minecraft 游戏的服务器地址列表
@MainActor
class ServerAddressService {
    static let shared = ServerAddressService()

    private init() {}

    /// 从游戏目录读取服务器地址列表（仅从 servers.dat 读取）
    /// - Parameter gameName: 游戏名称
    /// - Returns: 服务器地址列表
    func loadServerAddresses(for gameName: String) async throws -> [ServerAddress] {
        let profileDir = AppPaths.profileDirectory(gameName: gameName)
        let serversDatURL = profileDir.appendingPathComponent("servers.dat")

        guard FileManager.default.fileExists(atPath: serversDatURL.path) else {
            Logger.shared.debug("servers.dat 文件不存在: \(serversDatURL.path)")
            return []
        }
        Logger.shared.debug("开始读取 servers.dat: \(serversDatURL.path)")
        do {
            let response: ScslCoreCLIEnvelope<[ServerAddress]> = try await ScslCoreCLIService.shared.runJSON(
                arguments: ["game", "server-addresses-read", "--path", serversDatURL.path]
            )
            let servers = response.data
            Logger.shared.debug("成功解析 \(servers.count) 个服务器")
            return servers
        } catch {
            Logger.shared.warning("解析服务器地址 servers.dat 文件失败: \(error.localizedDescription)")
            // 解析失败时返回空数组，而不是抛出错误
            return []
        }
    }

    /// 保存服务器地址列表到游戏目录（保存为 servers.dat，NBT 格式）
    /// - Parameters:
    ///   - servers: 服务器地址列表
    ///   - gameName: 游戏名称
    /// - Throws: 保存错误
    func saveServerAddresses(_ servers: [ServerAddress], for gameName: String) async throws {
        let serversDatURL = AppPaths.profileDirectory(gameName: gameName)
            .appendingPathComponent("servers.dat")

        Logger.shared.debug("开始保存服务器地址列表到: \(serversDatURL.path)")
        let payload = try JSONEncoder().encode(servers)
        guard let json = String(data: payload, encoding: .utf8) else {
            throw ScslCoreCLIError.invalidUTF8
        }
        let _: ScslCoreCLIEnvelope<EmptyCLIResponse> = try await ScslCoreCLIService.shared.runJSON(
            arguments: ["game", "server-addresses-write", "--path", serversDatURL.path],
            standardInput: json
        )

        Logger.shared.debug("成功保存 \(servers.count) 个服务器地址到 servers.dat")
    }
}
