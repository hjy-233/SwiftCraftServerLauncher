import SwiftUI
import AppKit

struct RawConfigEditorView: View {
    let server: ServerInstance
    let item: ServerFileItem
    @EnvironmentObject var serverNodeRepository: ServerNodeRepository
    @StateObject private var generalSettings = GeneralSettingsManager.shared
    @State private var content = ""
    @State private var isLoaded = false
    @State private var isDirty = false
    @State private var contentAutoSaveTask: Task<Void, Never>?
    private let autoRefreshTimer = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(item.fileName)
                    .font(.headline)
                Spacer()
                Text(isDirty ? "server.properties.auto_save.saving".localized() : "server.properties.auto_save.saved".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !isLoaded {
                ProgressView()
            } else {
                LineNumberedTextEditor(
                    text: Binding(
                        get: { content },
                        set: { newValue in
                            content = newValue
                            markContentDirtyAndAutoSave()
                        }
                    ),
                    onSaveRequested: save,
                    syntaxKind: syntaxKind,
                    fontStyle: generalSettings.editorFontStyle,
                    highlightStyle: generalSettings.editorHighlightStyle
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: load)
        .onReceive(autoRefreshTimer) { _ in
            if !isDirty {
                load()
            }
        }
        .onDisappear {
            contentAutoSaveTask?.cancel()
            save()
        }
    }

    private func markContentDirtyAndAutoSave() {
        isDirty = true
        contentAutoSaveTask?.cancel()
        contentAutoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                save()
            }
        }
    }

    private func load() {
        guard !item.isDirectory else {
            isLoaded = true
            isDirty = false
            content = ""
            return
        }
        if server.nodeId != ServerNode.local.id {
            guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
            Task {
                do {
                    let text = try await SSHNodeService.readRemoteConfigFile(node: node, serverName: server.name, relativePath: item.relativePath)
                    await MainActor.run {
                        content = text
                        isLoaded = true
                        isDirty = false
                    }
                } catch {
                    await MainActor.run {
                        GlobalErrorHandler.shared.handle(error)
                        isLoaded = true
                        isDirty = false
                    }
                }
            }
            return
        }
        Task {
            do {
                let text = try await ServerFileService.readFile(server: server, relativePath: item.relativePath)
                await MainActor.run {
                    content = text
                    isLoaded = true
                    isDirty = false
                }
            } catch {
                await MainActor.run {
                    GlobalErrorHandler.shared.handle(error)
                    isLoaded = true
                    isDirty = false
                }
            }
        }
    }

    private func save() {
        if server.nodeId != ServerNode.local.id {
            guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
            Task {
                do {
                    try await SSHNodeService.writeRemoteConfigFile(
                        node: node,
                        serverName: server.name,
                        relativePath: item.relativePath,
                        content: content
                    )
                    await MainActor.run { isDirty = false }
                } catch {
                    await MainActor.run { GlobalErrorHandler.shared.handle(error) }
                }
            }
            return
        }
        Task {
            do {
                try await ServerFileService.writeFile(server: server, relativePath: item.relativePath, content: content)
                await MainActor.run { isDirty = false }
            } catch {
                await MainActor.run { GlobalErrorHandler.shared.handle(error) }
            }
        }
    }

    private var syntaxKind: SyntaxKind {
        switch URL(fileURLWithPath: item.relativePath).pathExtension.lowercased() {
        case "json":
            return .json
        case "yaml", "yml":
            return .yaml
        case "toml":
            return .toml
        case "ini", "cfg", "conf":
            return .ini
        default:
            if item.relativePath.lowercased().hasSuffix("server.properties") {
                return .properties
            }
            return .plain
        }
    }
}

private enum SyntaxKind {
    case plain
    case json
    case yaml
    case toml
    case properties
    case ini
}

private struct LineNumberedTextEditor: View {
    @Binding var text: String
    var onSaveRequested: (() -> Void)?
    var syntaxKind: SyntaxKind = .plain
    var fontStyle: EditorFontStyle = .monospaced
    var highlightStyle: HighlightStyle = .system

    var body: some View {
        LineNumberedTextEditorRepresentable(
            text: $text,
            onSaveRequested: onSaveRequested,
            syntaxKind: syntaxKind,
            fontStyle: fontStyle,
            highlightStyle: highlightStyle
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct LineNumberedTextEditorRepresentable: NSViewRepresentable {
    @Binding var text: String
    var onSaveRequested: (() -> Void)?
    var syntaxKind: SyntaxKind = .plain
    var fontStyle: EditorFontStyle = .monospaced
    var highlightStyle: HighlightStyle = .system

    func makeNSView(context: Context) -> LineNumberEditorContainer {
        let view = LineNumberEditorContainer()
        view.onTextChange = { newValue in
            if context.coordinator.isUpdatingFromSwiftUI {
                return
            }
            text = newValue
        }
        view.onSaveRequested = onSaveRequested
        view.syntaxKind = syntaxKind
        view.fontStyle = fontStyle
        view.highlightStyle = highlightStyle
        view.setText(text)
        return view
    }

    func updateNSView(_ nsView: LineNumberEditorContainer, context: Context) {
        nsView.onSaveRequested = onSaveRequested
        nsView.syntaxKind = syntaxKind
        nsView.fontStyle = fontStyle
        nsView.highlightStyle = highlightStyle
        if nsView.text != text {
            context.coordinator.isUpdatingFromSwiftUI = true
            nsView.setText(text)
            context.coordinator.isUpdatingFromSwiftUI = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var isUpdatingFromSwiftUI = false
    }
}

private final class LineNumberEditorContainer: NSView, NSTextViewDelegate {
    private let textScrollView = NSScrollView()
    private let textView = CommandAwareTextView()
    private var boundsObserver: NSObjectProtocol?
    private var isApplyingHighlight = false
    var onTextChange: ((String) -> Void)?
    var onSaveRequested: (() -> Void)? {
        didSet {
            textView.onSaveRequested = onSaveRequested
        }
    }
    var syntaxKind: SyntaxKind = .plain {
        didSet { applySyntaxHighlighting() }
    }
    var fontStyle: EditorFontStyle = .monospaced {
        didSet { applySyntaxHighlighting() }
    }
    var highlightStyle: HighlightStyle = .system {
        didSet { applySyntaxHighlighting() }
    }

    var text: String { textView.string }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
        setupObservers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
        setupObservers()
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    func setText(_ value: String) {
        textView.string = value
        applySyntaxHighlighting()
    }

    private func setupViews() {
        wantsLayer = true

        textView.frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.font = fontStyle.toFont(size: 13, weight: .regular)
        textView.textColor = NSColor.labelColor
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.delegate = self

        textScrollView.documentView = textView
        textScrollView.hasVerticalScroller = true
        textScrollView.hasHorizontalScroller = true
        textScrollView.autohidesScrollers = true
        textScrollView.borderType = .noBorder
        textScrollView.translatesAutoresizingMaskIntoConstraints = false
        textScrollView.contentView.postsBoundsChangedNotifications = true

        addSubview(textScrollView)

        NSLayoutConstraint.activate([
            textScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textScrollView.topAnchor.constraint(equalTo: topAnchor),
            textScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func setupObservers() {
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: textScrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.textScrollView.contentView.needsDisplay = true
        }
    }

    func textDidChange(_ notification: Notification) {
        applySyntaxHighlighting()
        onTextChange?(textView.string)
    }

    private func applySyntaxHighlighting() {
        guard !isApplyingHighlight else { return }
        guard let storage = textView.textStorage else { return }

        isApplyingHighlight = true
        defer { isApplyingHighlight = false }

        let fullRange = NSRange(location: 0, length: storage.length)
        let selectedRanges = textView.selectedRanges
        let font = fontStyle.toFont(size: 13, weight: .regular)
        let palette = EditorHighlightPalette(style: highlightStyle)

        storage.beginEditing()
        storage.setAttributes([
            .foregroundColor: NSColor.labelColor,
            .font: font,
        ], range: fullRange)

        highlightStrings(in: storage.string, storage: storage, color: palette.string)
        highlightNumbers(in: storage.string, storage: storage, color: palette.number)
        highlightBooleans(in: storage.string, storage: storage, color: palette.boolean)
        highlightKeys(in: storage.string, storage: storage, color: palette.key)
        highlightComments(in: storage.string, storage: storage, color: palette.comment)

        storage.endEditing()
        textView.selectedRanges = selectedRanges
    }

    private func highlightComments(in text: String, storage: NSTextStorage, color: NSColor) {
        let pattern: String
        switch syntaxKind {
        case .json:
            return
        case .yaml, .toml, .properties, .ini:
            pattern = #"(?m)^\s*[#;].*$|(?m)^\s*//.*$"#
        case .plain:
            pattern = #"(?m)^\s*[#;].*$|(?m)^\s*//.*$"#
        }
        applyRegex(pattern, color: color, text: text, storage: storage)
    }

    private func highlightStrings(in text: String, storage: NSTextStorage, color: NSColor) {
        let pattern = #""([^"\\]|\\.)*"|'([^'\\]|\\.)*'"#
        applyRegex(pattern, color: color, text: text, storage: storage)
    }

    private func highlightNumbers(in text: String, storage: NSTextStorage, color: NSColor) {
        let pattern = #"\b\d+(\.\d+)?\b"#
        applyRegex(pattern, color: color, text: text, storage: storage)
    }

    private func highlightBooleans(in text: String, storage: NSTextStorage, color: NSColor) {
        let pattern = #"\b(true|false|null|yes|no|on|off)\b"#
        applyRegex(pattern, color: color, text: text, storage: storage, options: [.caseInsensitive])
    }

    private func highlightKeys(in text: String, storage: NSTextStorage, color: NSColor) {
        let pattern: String
        let captureGroup: Int

        switch syntaxKind {
        case .json:
            pattern = #"(?m)^\s*"([^"]+)"\s*:"#
            captureGroup = 1
        case .yaml, .toml:
            pattern = #"(?m)^\s*([A-Za-z0-9_.-]+)\s*[:=]"#
            captureGroup = 1
        case .properties, .ini:
            pattern = #"(?m)^\s*([^#;\s][^=:\n]*?)\s*[:=]"#
            captureGroup = 1
        case .plain:
            pattern = #"(?m)^\s*([A-Za-z0-9_.-]+)\s*[:=]"#
            captureGroup = 1
        }

        applyRegex(
            pattern,
            color: color,
            text: text,
            storage: storage,
            options: [],
            captureGroup: captureGroup
        )
    }

    private func applyRegex(
        _ pattern: String,
        color: NSColor,
        text: String,
        storage: NSTextStorage,
        options: NSRegularExpression.Options = [],
        captureGroup: Int? = nil
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        regex.matches(in: text, range: range).forEach { match in
            let targetRange: NSRange
            if let captureGroup, match.numberOfRanges > captureGroup {
                targetRange = match.range(at: captureGroup)
            } else {
                targetRange = match.range
            }
            guard targetRange.location != NSNotFound else { return }
            storage.addAttribute(.foregroundColor, value: color, range: targetRange)
        }
    }
}

private struct EditorHighlightPalette {
    let string: NSColor
    let number: NSColor
    let boolean: NSColor
    let key: NSColor
    let comment: NSColor

    init(style: HighlightStyle) {
        switch style {
        case .system:
            string = .systemRed
            number = .systemOrange
            boolean = .systemPink
            key = .systemTeal
            comment = .systemGray
        case .vivid:
            string = .systemYellow
            number = .systemOrange
            boolean = .systemPurple
            key = .systemBlue
            comment = .systemGray
        }
    }
}

private extension EditorFontStyle {
    func toFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        switch self {
        case .system:
            return NSFont.systemFont(ofSize: size, weight: weight)
        case .monospaced:
            return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
    }
}

private final class CommandAwareTextView: NSTextView {
    var onSaveRequested: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if handleFindShortcuts(event) {
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleFindShortcuts(event) {
            return true
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        if key == "s" {
            onSaveRequested?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func handleFindShortcuts(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }
        if key == "f" {
            showFindPanel()
            return true
        }
        if modifiers.contains([.command, .shift]) && key == "g" {
            jumpFindResult(previous: true)
            return true
        }
        if modifiers.contains(.command) && key == "g" {
            jumpFindResult(previous: false)
            return true
        }
        return false
    }

    private func showFindPanel() {
        window?.makeFirstResponder(self)
        let item = NSMenuItem()
        item.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        performFindPanelAction(item)
    }

    private func jumpFindResult(previous: Bool) {
        window?.makeFirstResponder(self)
        let item = NSMenuItem()
        item.tag = Int(previous ? NSFindPanelAction.previous.rawValue : NSFindPanelAction.next.rawValue)
        performFindPanelAction(item)
    }
}
