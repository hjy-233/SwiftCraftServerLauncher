import SwiftUI

struct MainView: View {
    @StateObject private var general = GeneralSettingsManager.shared

    var body: some View {
        MainContentArea(interfaceLayoutStyle: general.interfaceLayoutStyle)
            .frame(minWidth: 900, minHeight: 500)
    }
}
