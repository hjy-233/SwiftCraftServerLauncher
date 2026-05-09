import SwiftUI

/// 窗口标识符枚举
enum WindowID: String {
    case about = "about"
    case contributors = "contributors"
    case serverDetail = "serverDetail"
}

extension WindowID: CaseIterable {}
