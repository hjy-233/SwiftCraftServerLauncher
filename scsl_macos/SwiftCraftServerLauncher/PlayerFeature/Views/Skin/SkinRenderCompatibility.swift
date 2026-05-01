import SwiftUI
import AppKit

enum PlayerModel {
    case steve
    case alex
}

struct SkinRenderView: View {
    private var skinImage: NSImage?
    private var texturePath: String?
    @Binding private var capeImage: NSImage?
    private var playerModel: PlayerModel
    private var rotationDuration: Double
    private var backgroundColor: NSColor
    private var onSkinDropped: ((NSImage) -> Void)?
    private var onCapeDropped: ((NSImage) -> Void)?

    init(
        skinImage: NSImage,
        capeImage: Binding<NSImage?>,
        playerModel: PlayerModel,
        rotationDuration: Double,
        backgroundColor: NSColor,
        onSkinDropped: ((NSImage) -> Void)? = nil,
        onCapeDropped: ((NSImage) -> Void)? = nil
    ) {
        self.skinImage = skinImage
        self.texturePath = nil
        self._capeImage = capeImage
        self.playerModel = playerModel
        self.rotationDuration = rotationDuration
        self.backgroundColor = backgroundColor
        self.onSkinDropped = onSkinDropped
        self.onCapeDropped = onCapeDropped
    }

    init(
        texturePath: String,
        capeImage: Binding<NSImage?>,
        playerModel: PlayerModel,
        rotationDuration: Double,
        backgroundColor: NSColor,
        onSkinDropped: ((NSImage) -> Void)? = nil,
        onCapeDropped: ((NSImage) -> Void)? = nil
    ) {
        self.skinImage = nil
        self.texturePath = texturePath
        self._capeImage = capeImage
        self.playerModel = playerModel
        self.rotationDuration = rotationDuration
        self.backgroundColor = backgroundColor
        self.onSkinDropped = onSkinDropped
        self.onCapeDropped = onCapeDropped
    }

    var body: some View {
        ZStack {
            Color(nsColor: backgroundColor).opacity(0.08)
            VStack(spacing: 6) {
                Image(systemName: "person.crop.rectangle.stack")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text("Skin preview disabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
