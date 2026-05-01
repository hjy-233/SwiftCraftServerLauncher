import AppKit
import SwiftUI

private enum TitlebarSeparatorHoverInstaller {
    static let hoverViewIdentifier = "titlebarHoverView"

    static func install(on window: NSWindow) {
        guard let titlebarView = window.standardWindowButton(.closeButton)?.superview else { return }

        window.titlebarSeparatorStyle = .none

        if let existing = titlebarView.subviews.first(where: {
            $0.identifier?.rawValue == hoverViewIdentifier
        }) as? TitlebarHoverView {
            existing.onHoverChanged = { isHovering in
                window.titlebarSeparatorStyle = isHovering ? .line : .none
            }
            return
        }

        let hoverView = TitlebarHoverView(frame: titlebarView.bounds)
        hoverView.identifier = NSUserInterfaceItemIdentifier(hoverViewIdentifier)
        hoverView.autoresizingMask = [.width, .height]
        hoverView.onHoverChanged = { isHovering in
            window.titlebarSeparatorStyle = isHovering ? .line : .none
        }
        titlebarView.addSubview(hoverView)
    }
}

private final class TitlebarHoverView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    private var trackingAreaRef: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        trackingAreaRef = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChanged?(false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
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
