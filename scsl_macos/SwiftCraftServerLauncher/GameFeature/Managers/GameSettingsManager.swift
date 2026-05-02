import Foundation
import SwiftUI

/// 数据源枚举
enum DataSource: String, CaseIterable, Codable {
    case modrinth = "Modrinth"

    var displayName: String {
        "Modrinth"
    }

    var localizedName: String {
        "settings.default_api_source.\(rawValue.lowercased())".localized()
    }
}

class GameSettingsManager: ObservableObject {
    // MARK: - 单例实例
    static let shared = GameSettingsManager()

    private struct CoreBackedGameSettings: Codable {
        struct BoolSetting: Codable {
            let value: Bool

            init(_ value: Bool) {
                self.value = value
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                self.value = try container.decode(Bool.self)
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode(value)
            }
        }

        let globalXms: Int?
        let globalXmx: Int?
        let enableAICrashAnalysis: BoolSetting?
        let defaultAPISource: String?
        let includeSnapshotsForGameVersions: BoolSetting?
    }

    private var isApplyingCoreSettings = false

    @AppStorage("globalXms")
    var globalXms: Int = 512 {
        didSet {
            persistCoreSettingsIfNeeded()
            objectWillChange.send()
        }
    }

    @AppStorage("globalXmx")
    var globalXmx: Int = 4096 {
        didSet {
            persistCoreSettingsIfNeeded()
            objectWillChange.send()
        }
    }

    @AppStorage("enableAICrashAnalysis")
    var enableAICrashAnalysis: Bool = false {
        didSet {
            persistCoreSettingsIfNeeded()
            objectWillChange.send()
        }
    }

    @AppStorage("defaultAPISource")
    var defaultAPISource: DataSource = .modrinth {
        didSet {
            if defaultAPISource != .modrinth {
                defaultAPISource = .modrinth
                return
            }
            persistCoreSettingsIfNeeded()
            objectWillChange.send()
        }
    }

    /// 是否在游戏版本选择中包含快照版（全局设置）
    @AppStorage("includeSnapshotsForGameVersions")
    var includeSnapshotsForGameVersions: Bool = false {
        didSet {
            persistCoreSettingsIfNeeded()
            objectWillChange.send()
        }
    }

    private init() {
        loadCoreSettings()
        persistCoreSettingsIfNeeded()
    }

    /// 计算系统最大可用内存分配（基于物理内存的70%）
    var maximumMemoryAllocation: Int {
        let physicalMemoryBytes = ProcessInfo.processInfo.physicalMemory
        let physicalMemoryMB = physicalMemoryBytes / 1_048_576
        let calculatedMax = Int(Double(physicalMemoryMB) * 0.7)
        let roundedMax = (calculatedMax / 512) * 512
        return max(roundedMax, 512)
    }

    private func loadCoreSettings() {
        do {
            let settings = try CoreSettingsBridge.read(
                CoreBackedGameSettings.self,
                scope: .game
            )
            isApplyingCoreSettings = true
            defer { isApplyingCoreSettings = false }
            if let globalXms = settings.globalXms {
                self.globalXms = globalXms
            }
            if let globalXmx = settings.globalXmx {
                self.globalXmx = globalXmx
            }
            if let enableAICrashAnalysis = settings.enableAICrashAnalysis?.value {
                self.enableAICrashAnalysis = enableAICrashAnalysis
            }
            if let defaultAPISource = settings.defaultAPISource,
               let source = DataSource(rawValue: defaultAPISource) {
                self.defaultAPISource = source
            }
            if let includeSnapshotsForGameVersions = settings.includeSnapshotsForGameVersions?.value {
                self.includeSnapshotsForGameVersions = includeSnapshotsForGameVersions
            }
        } catch {
            Logger.shared.warning("读取 core game settings 失败: \(error.localizedDescription)")
        }
    }

    private func persistCoreSettingsIfNeeded() {
        guard !isApplyingCoreSettings else { return }
        do {
            try CoreSettingsBridge.write(
                CoreBackedGameSettings(
                    globalXms: globalXms,
                    globalXmx: globalXmx,
                    enableAICrashAnalysis: .init(enableAICrashAnalysis),
                    defaultAPISource: defaultAPISource.rawValue,
                    includeSnapshotsForGameVersions: .init(includeSnapshotsForGameVersions)
                ),
                scope: .game
            )
        } catch {
            Logger.shared.warning("写入 core game settings 失败: \(error.localizedDescription)")
        }
    }
}
