import SwiftUI
import Foundation

/// 设置标签页枚举
enum SettingsTab: Int {
    case general = 0
    case generalBackup = 1
    case appearance = 2
    case mirrorSources = 3
    case ai = 4
}

/// 通用设置视图
/// 应用设置
public struct SettingsView: View {
    @EnvironmentObject private var settingsNavigation: SettingsNavigationManager

    public init() {}

    public var body: some View {
        TabView(selection: $settingsNavigation.selectedTab) {
            GeneralSettingsView(sections: [.basic, .update, .safety])
                .tabItem {
                    Label("settings.general.basic.tab".localized(), systemImage: "gearshape")
                }
                .tag(SettingsTab.general)

            GeneralSettingsView(sections: [.backup])
                .tabItem {
                    Label("settings.general.backup.tab".localized(), systemImage: "archivebox")
                }
                .tag(SettingsTab.generalBackup)

            AppearanceSettingsView()
                .tabItem {
                    Label("settings.appearance.tab".localized(), systemImage: "paintpalette")
                }
                .tag(SettingsTab.appearance)

            MirrorSourceSettingsView()
                .tabItem {
                    Label("settings.mirror.tab".localized(), systemImage: "link")
                }
                .tag(SettingsTab.mirrorSources)

            AISettingsView()
                .tabItem {
                    Label("settings.ai.tab".localized(), systemImage: "sparkles")
                }
                .tag(SettingsTab.ai)
        }
        .padding()
    }
}

struct CustomLabeledContentStyle: LabeledContentStyle {
    let alignment: VerticalAlignment

    init(alignment: VerticalAlignment = .center) {
        self.alignment = alignment
    }

    // 保留系统布局
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: alignment) {
            configuration.label
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            configuration.content
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

// 使用扩展避免破坏布局
extension LabeledContentStyle where Self == CustomLabeledContentStyle {
    static var custom: Self { .init() }

    static func custom(alignment: VerticalAlignment) -> Self {
        .init(alignment: alignment)
    }
}

#Preview {
    SettingsView()
}
