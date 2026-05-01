import Foundation
import SwiftUI

/// 语言管理器
/// 只负责语言列表与当前生效语言读取（不在 App 内修改语言）。
public class LanguageManager {
    /// 启动器支持的本地化代码（从 bundle 的实际本地化自动推导）。
    public static var supportedLanguageCodes: [String] {
        Bundle.main.localizations.filter { $0 != "Base" }
    }

    /// 当前对本 App 生效的语言 code（由系统设置与 bundle 自动解析）。
    public var selectedLanguage: String {
        Self.getDefaultLanguage()
    }

    /// 单例实例
    public static let shared = LanguageManager()

    private init() {}

    public static func getDefaultLanguage() -> String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    public static func displayName(for code: String, locale: Locale = .current) -> String {
        if let name = locale.localizedString(forIdentifier: code) {
            return name
        }
        return locale.localizedString(forIdentifier: "en") ?? "English"
    }

    public var selectedLanguageDisplayName: String {
        Self.displayName(for: selectedLanguage)
    }
}

// MARK: - String Localization Extension

extension String {
    /// 获取本地化字符串
    /// - Parameter bundle: 默认使用系统解析后的主 bundle
    /// - Returns: 本地化后的字符串
    public func localized(
        _ bundle: Bundle = .main
    ) -> String {
        bundle.localizedString(forKey: self, value: self, table: nil)
    }
}
