import SwiftUI
import AppKit

/// 窗口管理器，用于打开和关闭窗口（使用 Window，所有窗口都是单例）
@MainActor
class WindowManager {
    static let shared = WindowManager()

    private var openWindowAction: ((String) -> Void)?
    private var openWindowWithValueAction: ((String, String) -> Void)?

    private init() {}

    /// 设置窗口打开动作（由 WindowOpener 调用）
    func setOpenWindowAction(_ action: @escaping (String) -> Void) {
        self.openWindowAction = action
    }

    /// 设置带字符串参数的窗口打开动作（由 WindowOpener 调用）
    func setOpenWindowWithValueAction(_ action: @escaping (String, String) -> Void) {
        self.openWindowWithValueAction = action
    }

    /// 查找指定 ID 的窗口
    private func findWindow(id: WindowID) -> NSWindow? {
        let windows = NSApplication.shared.windows
        for window in windows {
            // 通过窗口的 identifier 查找匹配的窗口
            if let identifier = window.identifier?.rawValue,
               identifier == id.rawValue {
                return window
            }
        }
        return nil
    }

    /// 打开指定 ID 的窗口（Window 本身就是单例，会自动激活已存在的窗口）
    func openWindow(id: WindowID) {
        if let openWindow = openWindowAction {
            // 使用 OpenWindowAction 打开窗口（Window 会自动处理单例逻辑）
            openWindow(id.rawValue)
        } else {
            // 如果没有设置，通过通知中心通知主视图
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenWindow"),
                object: nil,
                userInfo: ["windowID": id.rawValue]
            )
        }
    }

    /// 打开指定 ID 的窗口并传入字符串参数（用于 WindowGroup(for:)）
    func openWindow(id: WindowID, value: String) {
        if let openWindow = openWindowWithValueAction {
            openWindow(id.rawValue, value)
        } else {
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenWindowWithValue"),
                object: nil,
                userInfo: ["windowID": id.rawValue, "windowValue": value]
            )
        }
    }

    /// 关闭指定 ID 的窗口
    func closeWindow(id: WindowID) {
        if let window = findWindow(id: id) {
            window.close()
        }
    }
}

/// 窗口打开器修饰符，用于在主视图中设置全局的 OpenWindowAction
struct WindowOpener: ViewModifier {
    @Environment(\.openWindow)
    private var openWindow

    func body(content: Content) -> some View {
        content
            .onAppear {
                // 设置全局窗口打开动作（使用闭包包装 OpenWindowAction）
                WindowManager.shared.setOpenWindowAction { windowID in
                    openWindow(id: windowID)
                }
                WindowManager.shared.setOpenWindowWithValueAction { windowID, value in
                    openWindow(id: windowID, value: value)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenWindow"))) { notification in
                // 监听通知并打开窗口（备用方案）
                if let windowIDString = notification.userInfo?["windowID"] as? String {
                    openWindow(id: windowIDString)
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: NSNotification.Name("OpenWindowWithValue"))
            ) { notification in
                if let windowIDString = notification.userInfo?["windowID"] as? String,
                   let windowValue = notification.userInfo?["windowValue"] as? String {
                    openWindow(id: windowIDString, value: windowValue)
                }
            }
    }
}

extension View {
    /// 应用窗口打开器配置
    func windowOpener() -> some View {
        modifier(WindowOpener())
    }
}
