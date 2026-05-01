import SwiftUI
import AppKit

struct ServerLogManagerView: View {
    let server: ServerInstance
    @State private var logEntries: [ServerLogEntry] = []
    @State private var loadError: String?
    @State private var selectedEntryId: ServerLogEntry.ID?
    @State private var previewEntry: ServerLogEntry?
    @State private var previewContent = ""
    @State private var previewError: String?
    @State private var isLoadingPreview = false
    @State private var showAISidebar = true
    @StateObject private var aiContextStore = LogAIContextStore()

    private var isRemoteServer: Bool {
        server.nodeId != ServerNode.local.id
    }

    var body: some View {
        ServerDetailPage(title: "server.logs.title".localized()) {
            VStack(alignment: .leading, spacing: 12) {
                if isRemoteServer {
                    ServerDetailEmptyState(text: "server.logs.remote_hint".localized())
                } else if let loadError {
                    ServerDetailEmptyState(text: loadError)
                } else if logEntries.isEmpty {
                    ServerDetailEmptyState(text: "server.logs.empty".localized())
                } else {
                    logTable
                }
            }
        }
        .onAppear { loadLogs() }
        .onChange(of: server.id) { _, _ in
            loadLogs()
        }
        .sheet(item: $previewEntry) { entry in
            logPreview(entry)
        }
    }

    private var logTable: some View {
        Table(logEntries, selection: $selectedEntryId) {
            TableColumn("server.logs.column.name".localized()) { entry in
                HStack(spacing: 8) {
                    Image(systemName: entry.iconName)
                        .foregroundStyle(.secondary)
                    Text(entry.displayName)
                        .lineLimit(1)
                }
                .onTapGesture {
                    openPreview(entry)
                }
            }
            TableColumn("server.logs.column.type".localized()) { entry in
                Text(entry.typeLabel)
                    .foregroundStyle(.secondary)
            }
            TableColumn("server.logs.column.modified".localized()) { entry in
                if let date = entry.modifiedAt {
                    Text(dateFormatter.string(from: date))
                        .foregroundStyle(.secondary)
                } else {
                    Text("-")
                        .foregroundStyle(.secondary)
                }
            }
            TableColumn("server.logs.column.size".localized()) { entry in
                Text(entry.sizeText)
                    .foregroundStyle(.secondary)
            }
        }
        .tableStyle(.inset)
        .onChange(of: selectedEntryId) { _, newValue in
            guard let newValue,
                  let entry = logEntries.first(where: { $0.id == newValue }) else { return }
            openPreview(entry)
        }
    }

    private func logPreview(_ entry: ServerLogEntry) -> some View {
        CommonSheetView {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.displayName)
                        .font(.headline)
                    Text(entry.url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showAISidebar.toggle()
                } label: {
                    Label(
                        "server.logs.ai_analyze".localized(),
                        systemImage: "sparkles"
                    )
                }
                .buttonStyle(.bordered)
                Button("server.logs.copy".localized()) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(previewContent, forType: .string)
                }
                .buttonStyle(.bordered)
                Button("server.logs.open_folder".localized()) {
                    NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                }
                .buttonStyle(.bordered)
            }
        } body: {
            HStack(spacing: 12) {
                if showAISidebar {
                    AILogAnalysisPanel(
                        serverName: server.name,
                        entry: entry,
                        session: aiContextStore.session(for: entry.id)
                    )
                    .frame(width: 300)
                }
                Group {
                    if isLoadingPreview {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else if let previewError {
                        Text(previewError)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ScrollView {
                            Text(previewContent)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        } footer: {
            EmptyView()
        }
        .frame(minWidth: 820, minHeight: 460)
        .onAppear {
            loadPreview(entry)
        }
    }

    private func loadLogs() {
        guard !isRemoteServer else {
            logEntries = []
            loadError = nil
            return
        }
        let baseDir = AppPaths.serverDirectory(serverName: server.directoryName)
        let logDir = baseDir.appendingPathComponent("logs", isDirectory: true)
        let crashDir = baseDir.appendingPathComponent("crash-reports", isDirectory: true)
        let logFiles = loadFiles(in: logDir).filter { url in
            isSupportedLog(url)
        }
        let crashFiles = loadFiles(in: crashDir)
        logEntries = makeEntries(logFiles: logFiles, crashFiles: crashFiles)
        loadError = nil
    }

    private func loadFiles(in directory: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return files.sorted { lhs, rhs in
            let ldate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rdate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return ldate > rdate
        }
    }

    private func isSupportedLog(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "log" { return true }
        if ext == "gz" {
            return url.deletingPathExtension().pathExtension.lowercased() == "log"
        }
        return false
    }

    private func makeEntries(logFiles: [URL], crashFiles: [URL]) -> [ServerLogEntry] {
        let logs = logFiles.map { ServerLogEntry(url: $0, kind: .log) }
        let crashes = crashFiles.map { ServerLogEntry(url: $0, kind: .crash) }
        return (logs + crashes).sorted { lhs, rhs in
            (lhs.modifiedAt ?? .distantPast) > (rhs.modifiedAt ?? .distantPast)
        }
    }

    private func openPreview(_ entry: ServerLogEntry) {
        previewEntry = entry
        selectedEntryId = entry.id
    }

    private func loadPreview(_ entry: ServerLogEntry) {
        isLoadingPreview = true
        previewError = nil
        previewContent = ""
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let content = try readContent(for: entry)
                DispatchQueue.main.async {
                    previewContent = content
                    isLoadingPreview = false
                }
            } catch {
                DispatchQueue.main.async {
                    previewError = error.localizedDescription
                    isLoadingPreview = false
                }
            }
        }
    }

    private func readContent(for entry: ServerLogEntry) throws -> String {
        if entry.isCompressed {
            let data = try decompressGzipWithSystem(at: entry.url)
            return String(bytes: data, encoding: .utf8) ?? ""
        }
        return try String(contentsOf: entry.url, encoding: .utf8)
    }

    private func decompressGzipWithSystem(at url: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        process.arguments = ["-c", url.path]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(domain: "ServerLog", code: 1, userInfo: [NSLocalizedDescriptionKey: "server.logs.error.decompress".localized()])
        }
        return data
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
}

private struct ServerLogEntry: Identifiable, Hashable {
    enum Kind {
        case log
        case crash
    }

    let url: URL
    let kind: Kind

    var id: String { url.path }

    var isCompressed: Bool {
        url.pathExtension.lowercased() == "gz"
    }

    var displayName: String {
        let base = url.deletingPathExtension().lastPathComponent
        if isCompressed {
            return URL(fileURLWithPath: base).deletingPathExtension().lastPathComponent
        }
        return base
    }

    var iconName: String {
        switch kind {
        case .log: return "doc.text"
        case .crash: return "exclamationmark.triangle"
        }
    }

    var typeLabel: String {
        switch kind {
        case .log: return "server.logs.type.log".localized()
        case .crash: return "server.logs.type.crash".localized()
        }
    }

    var modifiedAt: Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
    }

    var sizeText: String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

private struct AILogAnalysisPanel: View {
    let serverName: String
    let entry: ServerLogEntry
    @ObservedObject var session: LogAIChatSession
    @State private var isGenerating = false
    @State private var didSubmit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("server.logs.ai_analyze.title".localized())
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("server.logs.ai_sidebar.hint".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
            chatMessages
            HStack(spacing: 6) {
                TextField("server.logs.ai_prompt.placeholder".localized(), text: $session.draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { generate() }
                Button("server.logs.ai_send".localized()) {
                    generate()
                }
                .buttonStyle(.bordered)
                .disabled(isGenerating || session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var latestResponse: String? {
        session.chatState.messages.last { $0.role == .assistant }?.content
    }

    private var chatMessages: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(session.chatState.messages.filter { $0.role != .system }) { message in
                    HStack(alignment: .top) {
                        if message.role == .assistant {
                            Text(message.content)
                                .font(.system(.body))
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(Color(.windowBackgroundColor).opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        } else {
                            Spacer(minLength: 0)
                            Text(message.content)
                                .font(.system(.body))
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(Color.accentColor.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 180)
        .background(Color(.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func generate() {
        let userGoal = session.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userGoal.isEmpty else { return }
        ensureSystemPrompt()
        isGenerating = true
        didSubmit = true
        let attachments: [MessageAttachmentType]
        if session.chatState.messages.contains(where: { $0.role == .user }) == false {
            attachments = [.file(entry.url, entry.displayName)]
        } else {
            attachments = []
        }
        Task { @MainActor in
            await AIChatManager.shared.sendMessage(
                userGoal,
                attachments: attachments,
                chatState: session.chatState
            )
            session.draft = ""
            isGenerating = false
        }
    }

    private func ensureSystemPrompt() {
        if session.chatState.messages.contains(where: { $0.role == .system }) { return }
        let isChinese = LanguageManager.shared.selectedLanguage == "zh-Hans"
        let systemPrompt: String
        if isChinese {
            systemPrompt = """
            你是 Minecraft 服务器助手。请分析提供的服务器日志，重点找出错误、警告、可能的根因，并给出简洁的修复建议和下一步。你将基于用户问题进行对话式分析。
            服务器：\(serverName)
            日志文件：\(entry.url.lastPathComponent)
            """
        } else {
            systemPrompt = """
            You are a Minecraft server assistant. Analyze the provided server log for errors, warnings, and likely root causes.
            Provide concise fixes and next steps. Continue as a multi-turn conversation based on user questions.
            Server: \(serverName)
            Log file: \(entry.url.lastPathComponent)
            """
        }
        session.chatState.addMessage(ChatMessage(role: .system, content: systemPrompt))
    }
}

@MainActor
private final class LogAIChatSession: ObservableObject {
    let chatState = ChatState()
    @Published var draft: String = ""
}

@MainActor
private final class LogAIContextStore: ObservableObject {
    private var sessions: [ServerLogEntry.ID: LogAIChatSession] = [:]

    func session(for entryId: ServerLogEntry.ID) -> LogAIChatSession {
        if let existing = sessions[entryId] {
            return existing
        }
        let session = LogAIChatSession()
        sessions[entryId] = session
        return session
    }
}
