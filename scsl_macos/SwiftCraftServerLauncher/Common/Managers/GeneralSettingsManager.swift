import Combine
import Foundation
import SwiftUI

/// 主界面布局风格：经典（列表在左、内容在右）/ 聚焦（内容在左、列表在右）
public enum InterfaceLayoutStyle: String, CaseIterable {
    case classic = "classic"   // 经典
    case focused = "focused"  // 聚焦

    public var localizedName: String {
        "settings.interface_style.\(rawValue)".localized()
    }
}

public enum ThemeMode: String, CaseIterable {
    case light = "light"
    case dark = "dark"
    case system = "system"

    public var localizedName: String {
        "settings.theme.\(rawValue)".localized()
    }

    public var effectiveColorScheme: ColorScheme {
        switch self {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system:
            // 在主线程上安全访问系统外观
            if Thread.isMainThread {
                // 使用 NSApplication.shared 而不是 NSApp，更安全
                let appearance = NSApplication.shared.effectiveAppearance
                let bestMatch = appearance.bestMatch(from: [.aqua, .darkAqua])
                return bestMatch == .darkAqua ? .dark : .light
            } else {
                // 如果不在主线程，返回默认的 light 主题
                return .light
            }
        }
    }

    /// 对应的 AppKit 外观，用于影响基于 AppKit 的 UI（如 Sparkle）
    public var nsAppearance: NSAppearance? {
        switch self {
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        case .system:
            return nil
        }
    }
}

public enum AccentColorOption: String, CaseIterable, Identifiable {
    case system
    case blue
    case purple
    case pink
    case red
    case orange
    case yellow
    case green
    case gray

    public var id: String { rawValue }

    public var color: Color? {
        switch self {
        case .system:
            return nil
        case .blue:
            return Color(NSColor.systemBlue)
        case .purple:
            return Color(NSColor.systemPurple)
        case .pink:
            return Color(NSColor.systemPink)
        case .red:
            return Color(NSColor.systemRed)
        case .orange:
            return Color(NSColor.systemOrange)
        case .yellow:
            return Color(NSColor.systemYellow)
        case .green:
            return Color(NSColor.systemGreen)
        case .gray:
            return Color(NSColor.systemGray)
        }
    }
}

public enum ConsoleFontStyle: String, CaseIterable, Identifiable {
    case system
    case monospaced

    public var id: String { rawValue }
}

public enum EditorFontStyle: String, CaseIterable, Identifiable {
    case system
    case monospaced

    public var id: String { rawValue }
}

public enum HighlightStyle: String, CaseIterable, Identifiable {
    case system
    case vivid

    public var id: String { rawValue }
}

public enum ResourceCardStyle: String, CaseIterable, Identifiable {
    case compact
    case card

    public var id: String { rawValue }
}

class GeneralSettingsManager: ObservableObject, WorkingPathProviding {
    static let shared = GeneralSettingsManager()

    /// 是否启用 GitHub 代理（默认开启）
    @AppStorage("enableGitHubProxy")
    var enableGitHubProxy: Bool = true {
        didSet { objectWillChange.send() }
    }

    @AppStorage("gitProxyURL")
    var gitProxyURL: String = "https://gh-proxy.com" {
        didSet { objectWillChange.send() }
    }

    /// 是否启用资源页面本地缓存（默认开启）
    @AppStorage("enableResourcePageCache")
    var enableResourcePageCache: Bool = true {
        didSet { objectWillChange.send() }
    }

    /// 控制台彩色输出（默认开启）
    @AppStorage("enableConsoleColoredOutput")
    var enableConsoleColoredOutput: Bool = true {
        didSet { objectWillChange.send() }
    }

    // MARK: - 应用设置属性
    @AppStorage("concurrentDownloads")
    var concurrentDownloads: Int = 64 {
        didSet {
            if concurrentDownloads < 1 {
                concurrentDownloads = 1
            }
            objectWillChange.send()
        }
    }

    // 新增：启动器工作目录
    @AppStorage("launcherWorkingDirectory")
    var launcherWorkingDirectory: String = AppPaths.launcherSupportDirectory.path {
        didSet { objectWillChange.send() }
    }

    /// 界面风格：经典（列表 | 内容）/ 聚焦（内容 | 列表）
    @AppStorage("interfaceLayoutStyle")
    var interfaceLayoutStyle: InterfaceLayoutStyle = .focused {
        didSet {
            if interfaceLayoutStyle != .focused {
                interfaceLayoutStyle = .focused
                return
            }
            objectWillChange.send()
        }
    }

    @AppStorage("accentColorSelection")
    var accentColorSelection: AccentColorOption = .system {
        didSet { objectWillChange.send() }
    }

    var accentColor: Color? {
        accentColorSelection.color
    }

    @AppStorage("consoleFontStyle")
    var consoleFontStyle: ConsoleFontStyle = .monospaced {
        didSet { objectWillChange.send() }
    }

    @AppStorage("consoleLineSpacing")
    var consoleLineSpacing: Double = 2 {
        didSet { objectWillChange.send() }
    }

    @AppStorage("consoleHighlightStyle")
    var consoleHighlightStyle: HighlightStyle = .system {
        didSet { objectWillChange.send() }
    }

    @AppStorage("resourceCardStyle")
    var resourceCardStyle: ResourceCardStyle = .card {
        didSet { objectWillChange.send() }
    }

    @AppStorage("editorFontStyle")
    var editorFontStyle: EditorFontStyle = .monospaced {
        didSet { objectWillChange.send() }
    }

    @AppStorage("editorHighlightStyle")
    var editorHighlightStyle: HighlightStyle = .system {
        didSet { objectWillChange.send() }
    }

    // MARK: - 服务器管理外观

    @AppStorage("serverTabConsoleEnabled")
    var serverTabConsoleEnabled: Bool = true {
        didSet { objectWillChange.send() }
    }

    @AppStorage("serverTabConfigEnabled")
    var serverTabConfigEnabled: Bool = true {
        didSet { objectWillChange.send() }
    }

    @AppStorage("serverTabPlayersEnabled")
    var serverTabPlayersEnabled: Bool = true {
        didSet { objectWillChange.send() }
    }

    @AppStorage("serverTabWorldsEnabled")
    var serverTabWorldsEnabled: Bool = true {
        didSet { objectWillChange.send() }
    }

    @AppStorage("serverTabModsEnabled")
    var serverTabModsEnabled: Bool = true {
        didSet { objectWillChange.send() }
    }

    @AppStorage("serverTabPluginsEnabled")
    var serverTabPluginsEnabled: Bool = true {
        didSet { objectWillChange.send() }
    }

    @AppStorage("serverTabSchedulesEnabled")
    var serverTabSchedulesEnabled: Bool = true {
        didSet { objectWillChange.send() }
    }

    @AppStorage("serverTabLogsEnabled")
    var serverTabLogsEnabled: Bool = true {
        didSet { objectWillChange.send() }
    }

    @AppStorage("serverFileManagerShowShortcuts")
    var serverFileManagerShowShortcuts: Bool = true {
        didSet { objectWillChange.send() }
    }

    // MARK: - 启动 / 更新
    @AppStorage("launchAtLoginEnabled")
    var launchAtLoginEnabled: Bool = false {
        didSet { objectWillChange.send() }
    }

    @AppStorage("updateAutoCheckEnabled")
    var updateAutoCheckEnabled: Bool = true {
        didSet { objectWillChange.send() }
    }

    @AppStorage("updateAutoDownloadEnabled")
    var updateAutoDownloadEnabled: Bool = false {
        didSet { objectWillChange.send() }
    }

    // MARK: - 安全确认
    @AppStorage("confirmDeleteServer")
    var confirmDeleteServer: Bool = true {
        didSet { objectWillChange.send() }
    }

    @AppStorage("confirmDeleteWorld")
    var confirmDeleteWorld: Bool = true {
        didSet { objectWillChange.send() }
    }

    @AppStorage("confirmUninstallPluginMod")
    var confirmUninstallPluginMod: Bool = true {
        didSet { objectWillChange.send() }
    }

    @AppStorage("confirmExitWhileRunning")
    var confirmExitWhileRunning: Bool = true {
        didSet { objectWillChange.send() }
    }

    @AppStorage("autoAcceptServerEULA")
    var autoAcceptServerEULA: Bool = false {
        didSet { objectWillChange.send() }
    }

    @AppStorage("openServerInNewWindow")
    var openServerInNewWindow: Bool = false {
        didSet { objectWillChange.send() }
    }

    // MARK: - 备份
    @AppStorage("backupAutoEnabled")
    var backupAutoEnabled: Bool = false {
        didSet { objectWillChange.send() }
    }

    @AppStorage("backupIntervalMinutes")
    var backupIntervalMinutes: Int = 60 {
        didSet {
            if backupIntervalMinutes < 5 {
                backupIntervalMinutes = 5
            }
            objectWillChange.send()
        }
    }

    @AppStorage("backupKeepCount")
    var backupKeepCount: Int = 10 {
        didSet {
            if backupKeepCount < 1 {
                backupKeepCount = 1
            }
            objectWillChange.send()
        }
    }

    @AppStorage("backupDirectoryPath")
    var backupDirectoryPath: String = AppPaths.launcherSupportDirectory
        .appendingPathComponent("backups", isDirectory: true).path {
        didSet {
            let trimmed = backupDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                backupDirectoryPath = AppPaths.launcherSupportDirectory
                    .appendingPathComponent("backups", isDirectory: true).path
            } else {
                backupDirectoryPath = (trimmed as NSString).expandingTildeInPath
            }
            objectWillChange.send()
        }
    }

    @AppStorage("backupBeforeUpdate")
    var backupBeforeUpdate: Bool = true {
        didSet { objectWillChange.send() }
    }

    @AppStorage("backupLastTimestamp")
    var backupLastTimestamp: Double = 0 {
        didSet { objectWillChange.send() }
    }

    private init() {
        if interfaceLayoutStyle != .focused {
            interfaceLayoutStyle = .focused
        }
        let trimmed = backupDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let expanded = (trimmed as NSString).expandingTildeInPath
            if expanded != backupDirectoryPath {
                backupDirectoryPath = expanded
            }
        }
    }

    /// 当前启动器工作目录（WorkingPathProviding）
    /// 空时使用默认支持目录
    var currentWorkingPath: String {
        launcherWorkingDirectory.isEmpty ? AppPaths.launcherSupportDirectory.path : launcherWorkingDirectory
    }

    var workingPathWillChange: AnyPublisher<Void, Never> {
        objectWillChange.map { _ in () }.eraseToAnyPublisher()
    }
}
