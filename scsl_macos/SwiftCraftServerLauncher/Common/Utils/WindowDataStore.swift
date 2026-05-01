import SwiftUI

/// 窗口数据存储，用于在窗口间传递数据
@MainActor
class WindowDataStore: ObservableObject {
    static let shared = WindowDataStore()

    private init() {}
}
