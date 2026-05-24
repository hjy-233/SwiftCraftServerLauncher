import AppKit
import SwiftUI

private enum TitlebarSeparatorHoverInstaller {
    static let hoverViewIdentifier = "titlebarHoverView"

    static func install(on window: NSWindow) {
        guard let titlebarView = window.standardWindowButton(.closeButton)?.superview else { return }

        window.titlebarSeparatorStyle = .automatic

        if let existing = titlebarView.subviews.first(where: {
            $0.identifier?.rawValue == hoverViewIdentifier
        }) {
            existing.removeFromSuperview()
        }
    }
}

struct TitlebarSeparatorHoverModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            WindowAccessor(synchronous: false) { window in
                TitlebarSeparatorHoverInstaller.install(on: window)
            }
        )
    }
}

extension View {
    func titlebarSeparatorOnHover() -> some View {
        modifier(TitlebarSeparatorHoverModifier())
    }
}
