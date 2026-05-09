import Foundation
import AVFoundation
/// Minecraft 启动命令生成器（仅负责进程与认证，由 GameLaunchUseCase 对外暴露）
struct MinecraftLaunchCommand {
    let player: Player?
    let game: GameVersionInfo

    /// 启动游戏（静默版本）
    func launchGame() async {
        do {
            try await launchGameThrowing()
        } catch {
            await handleLaunchError(error)
        }
    }

    /// 停止游戏（使用当前 command 的 player+game 定位进程）
    func stopGame() async {
        let userId = player?.id ?? ""
        _ = GameProcessManager.shared.stopProcess(for: game.id, userId: userId)
    }

    /// 启动游戏（抛出异常版本）
    /// - Throws: GlobalError 当启动失败时
    func launchGameThrowing() async throws {
        // 在启动游戏前验证并刷新Token（如果需要）
        let validatedPlayer = try await validatePlayerTokenBeforeLaunch()
        let plan = try await GameLaunchCoreService.buildLaunchPlan(
            game: game,
            player: validatedPlayer
        )
        try await launchGameProcess(plan: plan)
    }

    /// 在启动游戏前验证玩家Token
    /// - Returns: 验证后的玩家对象
    /// - Throws: GlobalError 当验证失败时
    private func validatePlayerTokenBeforeLaunch() async throws -> Player? {
        guard let player = player else {
            Logger.shared.warning("没有选择玩家，使用默认认证参数")
            return nil
        }

        // 如果是离线账户，直接返回
        guard player.isOnlineAccount else {
            return player
        }

        Logger.shared.info("启动游戏前验证玩家 \(player.name) 的Token")

        // 启动前按需从 Keychain 为该玩家加载认证凭据（只针对当前玩家，避免一次性读取所有账号）
        var playerWithCredential = player
        if playerWithCredential.credential == nil {
            let dataManager = PlayerDataManager()
            if let credential = dataManager.loadCredential(userId: playerWithCredential.id) {
                playerWithCredential.credential = credential
            }
        }

        // 使用已加载/更新后的玩家对象验证并尝试刷新Token
        let authService = MinecraftAuthService.shared
        let validatedPlayer = try await authService.validateAndRefreshPlayerTokenThrowing(for: playerWithCredential)

        // 如果Token被更新了，需要保存到PlayerDataManager
        if validatedPlayer.authAccessToken != player.authAccessToken {
            Logger.shared.info("玩家 \(player.name) 的Token已更新，保存到数据管理器")
            await updatePlayerInDataManager(validatedPlayer)
        }

        return validatedPlayer
    }

    /// 更新PlayerDataManager中的玩家信息
    /// - Parameter updatedPlayer: 更新后的玩家对象
    private func updatePlayerInDataManager(_ updatedPlayer: Player) async {
        let dataManager = PlayerDataManager()
        let success = dataManager.updatePlayerSilently(updatedPlayer)
        if success {
            Logger.shared.debug("已更新玩家数据管理器中的Token信息")
            // 同步更新内存中的玩家列表（避免下次启动仍使用旧 token）
            NotificationCenter.default.post(
                name: PlayerSkinService.playerUpdatedNotification,
                object: nil,
                userInfo: ["updatedPlayer": updatedPlayer]
            )
        }
    }

    /// 启动游戏进程
    /// - Parameter plan: 启动计划
    /// - Throws: GlobalError 当启动失败时
    private func launchGameProcess(plan: GameLaunchPlanResponse) async throws {
        if game.modLoader != "vanilla" {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
        let javaExecutable = plan.javaPath
        guard !javaExecutable.isEmpty else {
            throw GlobalError.configuration(
                chineseMessage: "Java 路径未设置",
                i18nKey: "error.configuration.java_path_not_set",
                level: .popup
            )
        }

        let gameWorkingDirectory = URL(fileURLWithPath: plan.workingDirectory)

        Logger.shared.info("启动游戏进程: \(javaExecutable) \(plan.arguments.joined(separator: " "))")
        Logger.shared.info("游戏工作目录: \(gameWorkingDirectory.path)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: javaExecutable)
        process.arguments = plan.arguments
        process.currentDirectoryURL = gameWorkingDirectory

        if !plan.environment.isEmpty {
            var env = ProcessInfo.processInfo.environment
            for (key, value) in plan.environment {
                env[key] = value
            }
            process.environment = env
        }

        // 存储进程到管理器（会自动设置终止处理器）
        let userId = player?.id ?? ""
        GameProcessManager.shared.storeProcess(gameId: game.id, userId: userId, process: process)

        do {
            try process.run()

            // 进程启动后立即设置状态为运行中
            _ = await MainActor.run {
                GameStatusManager.shared.setGameRunning(gameId: game.id, userId: userId, isRunning: true)
            }
        } catch {
            Logger.shared.error("启动进程失败: \(error.localizedDescription)")

            // 启动失败时清理进程并重置状态
            _ = GameProcessManager.shared.stopProcess(for: game.id, userId: userId)
            _ = await MainActor.run {
                GameStatusManager.shared.setGameRunning(gameId: game.id, userId: userId, isRunning: false)
            }

            throw GlobalError.gameLaunch(
                chineseMessage: "启动游戏进程失败: \(error.localizedDescription)",
                i18nKey: "error.game_launch.process_failed",
                level: .popup
            )
        }
    }

    /// 处理启动错误
    /// - Parameter error: 启动错误
    private func handleLaunchError(_ error: Error) async {
        Logger.shared.error("启动游戏失败：\(error.localizedDescription)")

        // 使用全局错误处理器处理错误
        let globalError = GlobalError.from(error)
        GlobalErrorHandler.shared.handle(globalError)
    }
}
