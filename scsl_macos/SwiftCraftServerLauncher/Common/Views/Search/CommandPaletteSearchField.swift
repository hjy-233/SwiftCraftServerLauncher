import AppKit
import SwiftUI

struct CommandPaletteSearchField: NSViewRepresentable {
    let onActivate: () -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let field = CommandPaletteSearchFieldView()
        field.placeholderString = ""
        field.isEditable = false
        field.isEnabled = true
        field.onActivate = onActivate
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if let field = nsView as? CommandPaletteSearchFieldView {
            field.onActivate = onActivate
        }
    }
}

final class CommandPaletteSearchFieldView: NSSearchField {
    var onActivate: (() -> Void)?

    override var acceptsFirstResponder: Bool {
        false
    }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateMagnifierTint()
    }

    private func updateMagnifierTint() {
        guard let cell = cell as? NSSearchFieldCell,
              let searchButtonCell = cell.searchButtonCell else { return }
        let baseImage = searchButtonCell.image
        guard let baseImage else { return }
        let tinted = tintedImage(baseImage, color: NSColor.secondaryLabelColor)
        if let tinted {
            searchButtonCell.image = tinted
        }
    }

    private func tintedImage(_ image: NSImage, color: NSColor) -> NSImage? {
        let output = image.copy() as? NSImage ?? image
        output.lockFocus()
        color.set()
        let imageRect = NSRect(origin: .zero, size: output.size)
        imageRect.fill(using: .sourceAtop)
        output.unlockFocus()
        return output
    }
}
