import SwiftUI

final class SettingsNavigationManager: ObservableObject {
    static let shared = SettingsNavigationManager()

    @Published var selectedTab: SettingsTab = .general

    private init() {}
}
