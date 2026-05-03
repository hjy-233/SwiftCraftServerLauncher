import SwiftUI
import AppKit
import Dispatch
// swiftlint:disable file_length
// swiftlint:disable:next type_body_length
struct ServerConsoleView: View {
    let server: ServerInstance
    @StateObject private var console = ServerConsoleManager.shared
    @StateObject private var generalSettings = GeneralSettingsManager.shared
    @EnvironmentObject var serverNodeRepository: ServerNodeRepository
    @State private var commandText: String = ""
    @State private var remoteLogText: String = ""
    @State private var rconOutputText: String = ""
    @State private var remoteLogTask: Task<Void, Never>?
    @State private var localLogTask: Task<Void, Never>?
    @State private var localLogText: String = ""
    @State private var lastRemotePolledText: String = ""
    @State private var lastLocalPolledText: String = ""
    @State private var lastLocalLogFilePath: String = ""
    @State private var lastLocalLogOffset: UInt64 = 0
    @State private var localLogMonitor: DispatchSourceFileSystemObject?
    @State private var localLogFileDescriptor: CInt = -1
    @State private var isLocalLogLoading: Bool = false
    @State private var hasPendingLocalLogReload: Bool = false
    @State private var rconPort: String = "25575"
    @State private var rconPassword: String = ""
    @State private var lastRemoteLogError: String = ""
    @State private var commandHistory: [String] = []
    @State private var historyIndex: Int?
    @FocusState private var commandFieldFocused: Bool
    @State private var keyMonitor: Any?
    @State private var initialConsoleLines: [String] = []
    @State private var consoleEvent: ServerConsoleManager.ConsoleEvent?
    @State private var isRenderingConsole: Bool = false
    @State private var loadOlderToken: Int = 0
    @State private var scrollToLeadingToken: Int = 0

    var body: some View {
        ServerDetailPage(
            title: "server.console.title".localized()
        ) {
            terminalSurface
        }
        .onAppear {
            rconPort = String(server.rconPort)
            rconPassword = server.rconPassword
            commandText = console.commandDraft(for: server.id)
            loadCommandHistory()
            startRemoteLogPollingIfNeeded()
            startLocalLogPollingIfNeeded()
            installKeyMonitor()
            initialConsoleLines = console.logLines(for: server.id)
            isRenderingConsole = false
            scrollToLeadingToken += 1
        }
        .onChange(of: server.id) { _, _ in
            isRenderingConsole = true
            remoteLogText = ""
            rconOutputText = ""
            localLogText = ""
            lastRemotePolledText = ""
            lastLocalPolledText = ""
            lastLocalLogFilePath = ""
            lastLocalLogOffset = 0
            stopRemoteLogPolling()
            stopLocalLogPolling()
            rconPort = String(server.rconPort)
            rconPassword = server.rconPassword
            commandHistory = []
            historyIndex = nil
            commandText = console.commandDraft(for: server.id)
            loadCommandHistory()
            startRemoteLogPollingIfNeeded()
            startLocalLogPollingIfNeeded()
            initialConsoleLines = console.logLines(for: server.id)
            consoleEvent = nil
            isRenderingConsole = false
            scrollToLeadingToken += 1
        }
        .onDisappear {
            stopRemoteLogPolling()
            stopLocalLogPolling()
            removeKeyMonitor()
            isRenderingConsole = false
        }
        .onReceive(console.$latestEvent) { event in
            guard let event, event.serverId == server.id else { return }
            if isRemoteServer {
                consoleEvent = event
            } else {
                initialConsoleLines = console.logLines(for: server.id)
                consoleEvent = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverDetailToolbarAction)) { note in
            guard let action = ServerDetailToolbarActionBus.action(from: note) else { return }
            if action == .consoleClear {
                clearConsole()
            }
        }
        .onChange(of: commandText) { _, newValue in
            console.setCommandDraft(newValue, for: server.id)
        }
    }

    private var terminalSurface: some View {
        VStack(spacing: 0) {
            consoleOutput
            commandInput
        }
        .padding(10)
    }

    private var consoleOutput: some View {
        NativeTerminalRepresentable(
            initialLines: initialConsoleLines,
            event: isRemoteServer ? consoleEvent : nil,
            enableColor: generalSettings.enableConsoleColoredOutput,
            fontStyle: generalSettings.consoleFontStyle,
            lineSpacing: generalSettings.consoleLineSpacing,
            highlightStyle: generalSettings.consoleHighlightStyle,
            loadOlderToken: loadOlderToken,
            scrollToLeadingToken: scrollToLeadingToken
        )
        .frame(minHeight: 220)
        .overlay(alignment: .topTrailing) {
            if initialConsoleLines.count > 2_000 {
                Button("server.console.load_earlier_history".localized()) {
                    loadOlderToken += 1
                }
                .buttonStyle(.plain)
                .font(.caption)
                .padding(8)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isRenderingConsole {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("server.console.rendering_logs".localized())
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(10)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isRenderingConsole)
        .animation(.easeInOut(duration: 0.18), value: initialConsoleLines.count > 2_000)
    }

    private var commandInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            if shouldShowRconInputs {
                HStack(spacing: 8) {
                    TextField("server.console.rcon.port".localized(), text: $rconPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    SecureField("server.console.rcon.password".localized(), text: $rconPassword)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal, 8)
            }
            HStack(spacing: 8) {
                Text(">")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                TextField(
                    "",
                    text: $commandText
                )
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .focused($commandFieldFocused)
                    .onSubmit { sendCommand() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            Button("") { sendInterrupt() }
                .keyboardShortcut("c", modifiers: [.control])
                .frame(width: 0, height: 0)
                .hidden()
            Button("") { clearConsole() }
                .keyboardShortcut("l", modifiers: [.control])
                .frame(width: 0, height: 0)
                .hidden()
        }
    }

    private func sendCommand() {
        let text = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        commandText = ""
        console.setCommandDraft("", for: server.id)
        appendHistory(text)
        historyIndex = nil
        if text.lowercased() == "stop", isRemoteServer == false {
            scheduleStopStatusCheck()
        }
        if isRemoteServer {
            sendRemoteDirectCommand(text)
            return
        }
        if ServerProcessManager.shared.getProcess(for: server.id) != nil {
            console.send(serverId: server.id, command: text)
            return
        }
        if LocalServerDirectService.isDirectModeAvailable(server: server) {
            Task {
                do {
                    _ = try await Task.detached(priority: .userInitiated) {
                        try await LocalServerDirectService.sendCommand(server: server, command: text)
                    }.value
                } catch {
                    await MainActor.run {
                        GlobalErrorHandler.shared.handle(error)
                    }
                }
            }
            return
        }
        sendLocalRCONCommand(text)
    }

    private func sendInterrupt() {
        let isForce = true
        let hint = "[SCSL] 强制停止中..."
        console.appendExternal(serverId: server.id, text: "\(hint)\n")
        if isRemoteServer {
            guard let node = resolvedRemoteNode(nodeId: server.nodeId) else { return }
            Task {
                do {
                    try await SSHNodeService.sendRemoteInterrupt(node: node, serverName: server.name, force: isForce)
                    await MainActor.run {
                        ServerStatusManager.shared.setServerRunning(serverId: server.id, isRunning: false)
                        ServerStatusManager.shared.setServerLaunching(serverId: server.id, isLaunching: false)
                    }
                } catch {
                    GlobalErrorHandler.shared.handle(error)
                }
            }
            return
        }
        if ServerProcessManager.shared.getProcess(for: server.id) != nil {
            _ = ServerProcessManager.shared.stopProcess(for: server.id)
            return
        }
        if LocalServerDirectService.isDirectModeAvailable(server: server) {
            Task {
                do {
                    _ = try await Task.detached(priority: .userInitiated) {
                        try await LocalServerDirectService.sendInterrupt(server: server, force: isForce)
                    }.value
                    await MainActor.run {
                        ServerStatusManager.shared.setServerRunning(serverId: server.id, isRunning: false)
                        ServerStatusManager.shared.setServerLaunching(serverId: server.id, isLaunching: false)
                    }
                } catch {
                    GlobalErrorHandler.shared.handle(error)
                }
            }
        }
    }

    private var isRemoteServer: Bool {
        server.nodeId != ServerNode.local.id
    }

    private var isRconMode: Bool {
        false
    }

    private var shouldShowRconInputs: Bool {
        isRemoteServer && isRconMode
    }

    private func currentLocalLogSnapshot(serverName _: String) -> String {
        lastLocalPolledText
    }

    private func startRemoteLogPollingIfNeeded() {
        guard isRemoteServer else { return }
        remoteLogTask?.cancel()
        let nodeId = server.nodeId
        let serverName = server.name
        remoteLogTask = Task {
            await loadRemoteLog(nodeId: nodeId, serverName: serverName)
            while !Task.isCancelled {
                await loadRemoteLog(nodeId: nodeId, serverName: serverName)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func stopRemoteLogPolling() {
        remoteLogTask?.cancel()
        remoteLogTask = nil
    }

    private func startLocalLogPollingIfNeeded() {
        guard !isRemoteServer else { return }
        localLogTask?.cancel()
        teardownLocalLogMonitor()
        let serverName = server.directoryName
        localLogTask = Task {
            await loadLocalLog(serverName: serverName)
        }
    }

    private func stopLocalLogPolling() {
        localLogTask?.cancel()
        localLogTask = nil
        teardownLocalLogMonitor()
        isLocalLogLoading = false
        hasPendingLocalLogReload = false
    }

    @MainActor
    private func loadLocalLog(serverName: String) async {
        if isLocalLogLoading {
            hasPendingLocalLogReload = true
            return
        }
        isLocalLogLoading = true
        defer {
            isLocalLogLoading = false
            if hasPendingLocalLogReload {
                hasPendingLocalLogReload = false
                Task { @MainActor in
                    await loadLocalLog(serverName: serverName)
                }
            }
        }
        do {
            var arguments = ["server", "local-log-poll", server.id]
            if !lastLocalLogFilePath.isEmpty {
                arguments.append(contentsOf: ["--current-file-path", lastLocalLogFilePath])
            }
            arguments.append(contentsOf: ["--offset", String(lastLocalLogOffset)])
            let response: ScslCoreCLIEnvelope<LocalLogPollCLIResponse> = try await ScslCoreCLIService.shared.runJSON(
                arguments: arguments
            )
            let update = response.data
            let filePath = update.filePath ?? ""
            if lastLocalLogFilePath != filePath {
                lastLocalLogFilePath = filePath
                lastLocalPolledText = ""
                configureLocalLogMonitor(filePath: filePath, serverName: serverName)
            }
            lastLocalLogOffset = update.nextOffset
            if update.appendedText.isEmpty {
                return
            }

            let appended = update.appendedText.trimmingCharacters(in: .newlines)
            if !appended.isEmpty {
                let appendedLines = appended.components(separatedBy: .newlines)
                if !appendedLines.isEmpty {
                    initialConsoleLines.append(contentsOf: appendedLines)
                    if initialConsoleLines.count > 2_000 {
                        initialConsoleLines = Array(initialConsoleLines.suffix(2_000))
                    }
                }
            }
            let combined = lastLocalPolledText + update.appendedText
            lastLocalPolledText = combined
                .components(separatedBy: .newlines)
                .suffix(300)
                .joined(separator: "\n")
        } catch {}
    }

    private func configureLocalLogMonitor(filePath: String, serverName: String) {
        teardownLocalLogMonitor()
        guard !filePath.isEmpty else { return }
        let descriptor = open(filePath, O_EVTONLY)
        guard descriptor >= 0 else {
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete],
            queue: DispatchQueue.main
        )
        source.setEventHandler {
            let event = source.data
            if event.contains(.delete) || event.contains(.rename) {
                self.teardownLocalLogMonitor()
                Task { @MainActor in
                    await self.loadLocalLog(serverName: serverName)
                }
                return
            }
            Task { @MainActor in
                await self.loadLocalLog(serverName: serverName)
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        localLogFileDescriptor = descriptor
        localLogMonitor = source
        source.resume()
    }

    private func teardownLocalLogMonitor() {
        localLogMonitor?.cancel()
        localLogMonitor = nil
        localLogFileDescriptor = -1
    }

    @MainActor
    private func loadRemoteLog(nodeId: String, serverName: String) async {
        guard let node = resolvedRemoteNode(nodeId: nodeId) else {
            let line = "[SCSL] \("server.console.remote_node_missing".localized())"
            console.appendExternal(serverId: server.id, text: line + "\n")
            return
        }
        do {
            let text = try await SSHNodeService.fetchRemoteServerLog(node: node, serverName: serverName)
            let filtered = filterNoisyRconLifecycleLogs(text)
            let current = filtered.trimmingCharacters(in: .whitespacesAndNewlines)
            if !current.isEmpty {
                let delta = incrementalDelta(previous: lastRemotePolledText, current: current)
                if !delta.isEmpty {
                    console.appendExternal(serverId: server.id, text: delta + "\n")
                }
                lastRemotePolledText = current
            }
            lastRemoteLogError = ""
        } catch {
            let message = GlobalError.from(error).chineseMessage
            if message == "error.validation.server_not_selected" {
                // Ignore generic key-only errors from transient SSH polling failures.
                return
            }
            if message.contains("SSH 执行失败(exit=255)") {
                // SSH polling can flap while the remote server is actually running.
                // Do not spam console with transient transport errors.
                return
            }
            if message != lastRemoteLogError {
                let line = "[SCSL] \(message)"
                console.appendExternal(serverId: server.id, text: line + "\n")
            }
            lastRemoteLogError = message
        }
    }

    private func incrementalDelta(previous: String, current: String) -> String {
        if previous.isEmpty { return current }
        if current == previous { return "" }
        if current.hasPrefix(previous) {
            return String(current.dropFirst(previous.count)).trimmingCharacters(in: .newlines)
        }

        let previousLines = previous.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let currentLines = current.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let maxOverlap = min(previousLines.count, currentLines.count)

        var overlap = 0
        if maxOverlap > 0 {
            for count in stride(from: maxOverlap, through: 1, by: -1)
                where Array(previousLines.suffix(count)) == Array(currentLines.prefix(count)) {
                overlap = count
                break
            }
        }

        let newLines = currentLines.dropFirst(overlap)
        return newLines.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    private func sendRemoteDirectCommand(_ command: String) {
        guard let node = resolvedRemoteNode(nodeId: server.nodeId) else {
            GlobalErrorHandler.shared.handle(
                GlobalError.validation(
                    chineseMessage: "未找到远程节点，请重新选择节点后重试",
                    i18nKey: "server.console.remote_node_missing",
                    level: .notification
                )
            )
            return
        }
        Task {
            do {
                try await SSHNodeService.sendRemoteDirectCommand(node: node, serverName: server.name, command: command)
            } catch {
                GlobalErrorHandler.shared.handle(error)
            }
        }
    }

    private func sendLocalRCONCommand(_ command: String) {
        Task {
            do {
                let response: ScslCoreCLIEnvelope<RconCLIResponse> = try await ScslCoreCLIService.shared.runJSON(
                    arguments: ["server", "rcon", server.id, command]
                )
                let output = response.data.output
                await MainActor.run {
                    if !output.isEmpty {
                        console.appendExternal(
                            serverId: server.id,
                            text: "[RCON] \(output.trimmingCharacters(in: .whitespacesAndNewlines))\n"
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    GlobalErrorHandler.shared.handle(error)
                }
            }
        }
    }

    private struct RconCLIResponse: Decodable {
        let output: String
    }

    private struct LocalLogPollCLIResponse: Decodable {
        let filePath: String?
        let appendedText: String
        let nextOffset: UInt64
    }

    private func filterNoisyRconLifecycleLogs(_ raw: String) -> String {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var kept: [String] = []
        kept.reserveCapacity(lines.count)

        for line in lines {
            let sanitized = line.unicodeScalars
                .filter { scalar in
                    scalar.value == 9 || scalar.value == 27 || scalar.value >= 32
                }
                .map(String.init)
                .joined()

            let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed == ">" { continue }
            if trimmed.allSatisfy({ $0 == ">" || $0 == " " }) { continue }
            if trimmed.range(of: #"^>+$"#, options: .regularExpression) != nil { continue }
            if sanitized.contains("RCON Client /127.0.0.1"),
               sanitized.contains("started") || sanitized.contains("shutting down") {
                continue
            }
            kept.append(sanitized)
        }

        return kept.joined(separator: "\n")
    }

    private func colorForLine(_ line: String) -> Color {
        let upper = line.uppercased()
        if upper.contains("ERROR") || line.contains("❌") || line.contains("Exception") {
            return .red
        }
        if upper.contains("WARN") || line.contains("⚠️") {
            return .yellow
        }
        if upper.contains("INFO") || line.contains("ℹ️") {
            return .green
        }
        if line.range(of: #"\b\d{2}:\d{2}:\d{2}\b"#, options: .regularExpression) != nil {
            return .blue
        }
        if line.contains("[") && line.contains("]") {
            return .primary
        }
        if upper.contains("PLUGIN")
            || upper.contains("PAPER")
            || upper.contains("FABRIC")
            || upper.contains("FORGE") {
            return .purple
        }
        if line.hasPrefix("[SCSL]") || line.hasPrefix("[RCON]") {
            return .cyan
        }
        return .primary
    }

    private func ansiStyledAttributedText(from text: String) -> AttributedString {
        let normalized = normalizeANSIText(text)
        var result = AttributedString()
        var currentColor: Color = .primary
        var isBold = false
        var buffer = ""
        let chars = Array(normalized)
        var index = 0

        while index < chars.count {
            if chars[index] == "\u{001B}", index + 1 < chars.count, chars[index + 1] == "[" {
                if !buffer.isEmpty {
                    appendStyledSegment(buffer, color: currentColor, isBold: isBold, to: &result)
                    buffer = ""
                }
                index += 2
                var codeBuffer = ""
                while index < chars.count, chars[index] != "m" {
                    codeBuffer.append(chars[index])
                    index += 1
                }
                if index < chars.count, chars[index] == "m" {
                    let codes = codeBuffer.split(separator: ";").compactMap { Int($0) }
                    let parsed = codes.isEmpty ? [0] : codes
                    var i = 0
                    while i < parsed.count {
                        let code = parsed[i]
                        switch code {
                        case 0:
                            currentColor = .primary
                            isBold = false
                        case 1:
                            isBold = true
                        case 22:
                            isBold = false
                        case 30...37, 90...97:
                            currentColor = ansiColor(code) ?? currentColor
                        case 39:
                            currentColor = .primary
                        case 38:
                            if i + 2 < parsed.count, parsed[i + 1] == 5 {
                                currentColor = ansi256Color(parsed[i + 2])
                                i += 2
                            } else if i + 4 < parsed.count, parsed[i + 1] == 2 {
                                let r = parsed[i + 2]
                                let g = parsed[i + 3]
                                let b = parsed[i + 4]
                                currentColor = Color(
                                    red: Double(max(0, min(255, r))) / 255.0,
                                    green: Double(max(0, min(255, g))) / 255.0,
                                    blue: Double(max(0, min(255, b))) / 255.0
                                )
                                i += 4
                            }
                        default:
                            break
                        }
                        i += 1
                    }
                }
            } else {
                buffer.append(chars[index])
            }
            index += 1
        }

        if !buffer.isEmpty {
            appendStyledSegment(buffer, color: currentColor, isBold: isBold, to: &result)
        }
        return result
    }

    private func normalizeANSIText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\u001B[", with: "\u{001B}[")
            .replacingOccurrences(of: "\\u001b[", with: "\u{001B}[")
            .replacingOccurrences(of: "\\u{001B}[", with: "\u{001B}[")
            .replacingOccurrences(of: "\\u{001b}[", with: "\u{001B}[")
            .replacingOccurrences(of: "\\x1b[", with: "\u{001B}[")
            .replacingOccurrences(of: "\\x1B[", with: "\u{001B}[")
            .replacingOccurrences(of: "\\033[", with: "\u{001B}[")
    }

    private func containsANSISequence(_ text: String) -> Bool {
        text.contains("\u{001B}[")
            || text.contains("\\u001B[")
            || text.contains("\\u001b[")
            || text.contains("\\u{001B}[")
            || text.contains("\\u{001b}[")
            || text.contains("\\x1b[")
            || text.contains("\\x1B[")
            || text.contains("\\033[")
    }

    private func appendStyledSegment(_ text: String, color: Color, isBold: Bool, to result: inout AttributedString) {
        guard !text.isEmpty else { return }
        var seg = AttributedString(text)
        var attrs = AttributeContainer()
        attrs.foregroundColor = color
        attrs.font = .system(.caption, design: .monospaced).weight(isBold ? .bold : .regular)
        seg.mergeAttributes(attrs)
        result.append(seg)
    }

    private func ansiColor(_ code: Int) -> Color? {
        switch code {
        case 30: return Color(nsColor: .black)
        case 31: return Color(nsColor: .systemRed)
        case 32: return Color(nsColor: .systemGreen)
        case 33: return Color(nsColor: .systemYellow)
        case 34: return Color(nsColor: .systemBlue)
        case 35: return Color(nsColor: .systemPink)
        case 36: return Color(nsColor: .systemTeal)
        case 37: return Color(nsColor: .white)
        case 90: return Color(nsColor: .systemGray)
        case 91: return Color(nsColor: .systemRed).opacity(0.95)
        case 92: return Color(nsColor: .systemGreen).opacity(0.95)
        case 93: return Color(nsColor: .systemYellow).opacity(0.95)
        case 94: return Color(nsColor: .systemBlue).opacity(0.95)
        case 95: return Color(nsColor: .systemPink).opacity(0.95)
        case 96: return Color(nsColor: .systemTeal).opacity(0.95)
        case 97: return Color(nsColor: .white).opacity(0.98)
        default: return nil
        }
    }

    private func ansi256Color(_ code: Int) -> Color {
        let clamped = max(0, min(255, code))
        if clamped < 16 {
            let base: [Color] = [
                .black, .red, .green, .yellow, .blue, .pink, .cyan, .white,
                .gray, .red, .green, .yellow, .blue, .pink, .cyan, .white,
            ]
            return base[clamped]
        }
        if clamped <= 231 {
            let n = clamped - 16
            let r = n / 36
            let g = (n % 36) / 6
            let b = n % 6
            let map = [0, 95, 135, 175, 215, 255]
            return Color(
                red: Double(map[r]) / 255.0,
                green: Double(map[g]) / 255.0,
                blue: Double(map[b]) / 255.0
            )
        }
        let gray = Double((clamped - 232) * 10 + 8) / 255.0
        return Color(red: gray, green: gray, blue: gray)
    }

    private func shouldRetryRcon(error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        return text.contains("connection refused")
            || text.contains("timed out")
            || text.contains("eof")
            || text.contains("连接失败")
    }

    private func resolvedRemoteNode(nodeId: String) -> ServerNode? {
        if let node = serverNodeRepository.getNode(by: nodeId), !node.isLocal {
            return node
        }
        let remoteNodes = serverNodeRepository.nodes.filter { !$0.isLocal }
        if remoteNodes.count == 1 {
            return remoteNodes.first
        }
        return nil
    }

    private func historyFileURL() -> URL {
        let base: URL
        if server.nodeId == ServerNode.local.id {
            base = AppPaths.serverDirectory(serverName: server.directoryName)
        } else {
            base = AppPaths.remoteNodeServersDirectory(nodeId: server.nodeId)
                .appendingPathComponent(server.name)
        }
        return base.appendingPathComponent(".console_history")
    }

    private func loadCommandHistory() {
        let url = historyFileURL()
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            commandHistory = normalizeHistoryContent(content)
            saveCommandHistory()
        } else {
            commandHistory = []
        }
    }

    private func saveCommandHistory() {
        let url = historyFileURL()
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let trimmed = Array(commandHistory.suffix(300))
        let data = trimmed.joined(separator: "\n") + (trimmed.isEmpty ? "" : "\n")
        try? data.write(to: url, atomically: true, encoding: .utf8)
    }

    private func appendHistory(_ command: String) {
        guard !command.isEmpty else { return }
        if commandHistory.last != command {
            commandHistory.append(command)
            saveCommandHistory()
        }
    }

    private func navigateHistoryUp() {
        guard !commandHistory.isEmpty else { return }
        if let index = historyIndex {
            historyIndex = max(0, index - 1)
        } else {
            historyIndex = commandHistory.count - 1
        }
        if let index = historyIndex {
            commandText = commandHistory[index]
        }
    }

    private func navigateHistoryDown() {
        guard !commandHistory.isEmpty else { return }
        guard let index = historyIndex else { return }
        let next = index + 1
        if next >= commandHistory.count {
            historyIndex = nil
            commandText = ""
        } else {
            historyIndex = next
            commandText = commandHistory[next]
        }
    }

    private func normalizeHistoryContent(_ content: String) -> [String] {
        let timestampPattern = #"(\\d{10,}:)"#
        let expanded = content.replacingOccurrences(
            of: timestampPattern,
            with: "\n$1",
            options: .regularExpression
        )
        let lines = expanded
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        var normalized: [String] = []
        for line in lines {
            if line.isEmpty { continue }
            let command: String
            if let range = line.range(of: #"^\d{10,}:"#, options: .regularExpression) {
                command = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                command = line
            }
            if command.isEmpty { continue }
            if normalized.last != command {
                normalized.append(command)
            }
        }
        return normalized
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard commandFieldFocused else { return event }
            switch event.keyCode {
            case 126:
                navigateHistoryUp()
                return nil
            case 125:
                navigateHistoryDown()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

private struct NativeTerminalRepresentable: NSViewRepresentable {
    let initialLines: [String]
    let event: ServerConsoleManager.ConsoleEvent?
    let enableColor: Bool
    let fontStyle: ConsoleFontStyle
    let lineSpacing: Double
    let highlightStyle: HighlightStyle
    let loadOlderToken: Int
    let scrollToLeadingToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .none

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.font = fontStyle.toFont(size: 12, weight: .medium)
        textView.textContainerInset = NSSize(width: 10, height: 8)
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
        textView.defaultParagraphStyle = paragraphStyle()
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.frame = NSRect(x: 0, y: 0, width: 640, height: 220)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byCharWrapping
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.setFrameSize(NSSize(width: scrollView.contentSize.width, height: textView.frame.size.height))

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.enableColor = enableColor
        context.coordinator.fontStyle = fontStyle
        context.coordinator.lineSpacing = lineSpacing
        context.coordinator.highlightStyle = highlightStyle
        context.coordinator.setInitial(lines: initialLines)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.enableColor = enableColor
        context.coordinator.updateStyle(
            fontStyle: fontStyle,
            lineSpacing: lineSpacing,
            highlightStyle: highlightStyle
        )
        if let textView = context.coordinator.textView {
            let width = nsView.contentSize.width
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.containerSize = NSSize(
                width: width,
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.minSize = NSSize(width: width, height: 0)
            textView.maxSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            textView.setFrameSize(NSSize(width: width, height: textView.frame.size.height))
        }
        context.coordinator.updateInitialIfNeeded(lines: initialLines)
        context.coordinator.apply(event: event)
        context.coordinator.loadOlderIfNeeded(token: loadOlderToken)
        context.coordinator.scrollToLeadingIfNeeded(token: scrollToLeadingToken)
    }

    private func paragraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byCharWrapping
        style.lineSpacing = max(0, lineSpacing)
        return style
    }

    final class Coordinator {
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var enableColor: Bool = true
        var fontStyle: ConsoleFontStyle = .monospaced
        var lineSpacing: Double = 2
        var highlightStyle: HighlightStyle = .system
        private var lines: [String] = []
        private var olderLines: [String] = []
        private var lastSequence: Int = 0
        private var lastLoadOlderToken: Int = 0
        private var lastScrollToLeadingToken: Int = 0
        private let maxRealtimeLines = 2_000
        private let olderBatchSize = 500

        func setInitial(lines: [String]) {
            let filtered = lines.compactMap(normalizeLogLine)
            if filtered.count > maxRealtimeLines {
                let splitIndex = filtered.count - maxRealtimeLines
                olderLines = Array(filtered[..<splitIndex])
                self.lines = Array(filtered[splitIndex...])
            } else {
                olderLines = []
                self.lines = filtered
            }
            redrawAll(keepAtBottom: true)
        }

        func updateInitialIfNeeded(lines: [String]) {
            let filtered = lines.compactMap(normalizeLogLine)
            let current = olderLines + self.lines
            guard filtered != current else { return }
            setInitial(lines: lines)
        }

        func updateStyle(
            fontStyle: ConsoleFontStyle,
            lineSpacing: Double,
            highlightStyle: HighlightStyle
        ) {
            let needsRedraw = self.fontStyle != fontStyle
                || self.lineSpacing != lineSpacing
                || self.highlightStyle != highlightStyle
            self.fontStyle = fontStyle
            self.lineSpacing = lineSpacing
            self.highlightStyle = highlightStyle
            if let textView {
                textView.font = fontStyle.toFont(size: 12, weight: .regular)
                let style = NSMutableParagraphStyle()
                style.lineBreakMode = .byCharWrapping
                style.lineSpacing = max(0, lineSpacing)
                textView.defaultParagraphStyle = style
            }
            if needsRedraw {
                redrawAll(keepAtBottom: false)
            }
        }

        func apply(event: ServerConsoleManager.ConsoleEvent?) {
            guard let event, event.sequence != lastSequence else { return }
            lastSequence = event.sequence
            switch event.kind {
            case .clear:
                olderLines.removeAll()
                lines.removeAll()
                textView?.textStorage?.setAttributedString(NSAttributedString())
            case .append:
                append(text: event.text)
            }
        }

        func loadOlderIfNeeded(token: Int) {
            guard token != lastLoadOlderToken else { return }
            lastLoadOlderToken = token
            guard !olderLines.isEmpty else { return }
            let take = min(olderBatchSize, olderLines.count)
            let start = olderLines.count - take
            let batch = Array(olderLines[start...])
            olderLines.removeSubrange(start...)
            lines = batch + lines
            redrawAll(keepAtBottom: false)
        }

        func scrollToLeadingIfNeeded(token: Int) {
            guard token != lastScrollToLeadingToken else { return }
            lastScrollToLeadingToken = token
            guard let scrollView else { return }
            let currentOrigin = scrollView.contentView.bounds.origin
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: currentOrigin.y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func append(text: String) {
            guard !text.isEmpty else { return }
            let incomingLines = splitChunkIntoCandidateLines(text)
                .compactMap(normalizeLogLine)
            guard !incomingLines.isEmpty else { return }
            lines.append(contentsOf: incomingLines)
            if lines.count > maxRealtimeLines {
                lines.removeFirst(lines.count - maxRealtimeLines)
                redrawAll(keepAtBottom: true)
                return
            }
            guard let storage = textView?.textStorage else { return }
            if storage.length > 0 {
                storage.append(NSAttributedString(string: "\n"))
            }
            storage.append(styledText(incomingLines.joined(separator: "\n")))
            scrollToBottom()
        }

        private func splitChunkIntoCandidateLines(_ raw: String) -> [String] {
            // 某些日志源会把多条记录粘在一行，这里在时间戳头部前强制断行
            let withSplitMarkers = raw.replacingOccurrences(
                of: #"(?<=\S)(?=\[\d{2}[:.]\d{2}[:.]\d{2}\])"#,
                with: "\n",
                options: .regularExpression
            )
            return withSplitMarkers.components(separatedBy: .newlines)
        }

        private func normalizeLogLine(_ raw: String) -> String? {
            // 1) 去 ANSI 序列
            let noAnsi = raw.replacingOccurrences(
                of: #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#,
                with: "",
                options: .regularExpression
            )
            // 某些日志源会丢失 ESC 字符，仅残留如 [33m / [0m，单独再清洗一次
            let noAnsiFragments = noAnsi.replacingOccurrences(
                of: #"\[[0-9;]{1,}(m|K|J|H|f)"#,
                with: "",
                options: .regularExpression
            )
            // 2) 去不可见控制字符（保留 tab）
            let cleaned = noAnsiFragments.unicodeScalars
                .filter { scalar in
                    scalar.value == 9 || scalar.value >= 32
                }
                .map(String.init)
                .joined()
            // 3) 收尾空白
            let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            // 4) 过滤 MC 提示符噪声
            if trimmed.range(of: #"^>+\s*$"#, options: .regularExpression) != nil {
                return nil
            }
            // 5) 过滤纯 0 噪声行（常见于异常控制字符清洗后的残留）
            if trimmed.range(of: #"^0+$"#, options: .regularExpression) != nil {
                return nil
            }
            return trimmed
        }

        private func redrawAll(keepAtBottom: Bool) {
            guard let storage = textView?.textStorage else { return }
            storage.setAttributedString(styledText(lines.joined(separator: "\n")))
            if keepAtBottom {
                scrollToBottom()
            }
        }

        private func scrollToBottom() {
            guard let textView else { return }
            textView.scrollToEndOfDocument(nil)
        }

        private func styledText(_ text: String) -> NSAttributedString {
            let font = fontStyle.toFont(size: 12, weight: .regular)
            guard enableColor else {
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineBreakMode = .byCharWrapping
                paragraphStyle.lineSpacing = max(0, lineSpacing)
                return NSAttributedString(string: text, attributes: [
                    .font: font,
                    .foregroundColor: NSColor.textColor,
                    .paragraphStyle: paragraphStyle,
                ])
            }
            let result = NSMutableAttributedString()
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byCharWrapping
            paragraphStyle.lineSpacing = max(0, lineSpacing)
            let splitLines = text.components(separatedBy: .newlines)
            for (index, line) in splitLines.enumerated() {
                result.append(styledLine(line, font: font, paragraphStyle: paragraphStyle))
                if index < splitLines.count - 1 {
                    result.append(NSAttributedString(string: "\n", attributes: [
                        .font: font,
                        .paragraphStyle: paragraphStyle,
                    ]))
                }
            }
            return result
        }

        private func styledLine(
            _ line: String,
            font: NSFont,
            paragraphStyle: NSParagraphStyle
        ) -> NSAttributedString {
            let attributed = NSMutableAttributedString(string: line, attributes: [
                .font: font,
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: paragraphStyle,
            ])
            let ns = line as NSString
            let fullRange = NSRange(location: 0, length: ns.length)
            let palette = ConsoleHighlightPalette(style: highlightStyle)

            func paint(_ pattern: String, color: NSColor, options: NSRegularExpression.Options = []) {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
                for match in regex.matches(in: line, range: fullRange) {
                    attributed.addAttribute(.foregroundColor, value: color, range: match.range)
                }
            }

            paint(#"\b\d{2}[:.]\d{2}[:.]\d{2}\b"#, color: palette.timestamp)
            // Example: "[21:18:23]"
            paint(#"\[\d{2}[:.]\d{2}[:.]\d{2}\]"#, color: palette.timestamp)
            // Example: "10 4月2026 21:18:23.873" (some logs omit whitespace: "104月2026 ...")
            // Avoid `\b` here: ICU word boundary rules + Chinese chars can cause misses.
            if let cnDateRegex = try? NSRegularExpression(
                pattern: #"(^|\s)(\d{1,2}\s*\d{1,2}月\d{4}\s+\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?)"#
            ) {
                for match in cnDateRegex.matches(in: line, range: fullRange) where match.numberOfRanges >= 3 {
                    attributed.addAttribute(.foregroundColor, value: palette.timestamp, range: match.range(at: 2))
                }
            }
            // Example: "[10 4月2026 21:18:23.873]" or "[104月2026 21:18:23.873]"
            paint(#"\[\d{1,2}\s*\d{1,2}月\d{4}\s+\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?\]"#, color: palette.timestamp)
            paint(#"\bINFO\b"#, color: palette.info, options: [.caseInsensitive])
            paint(#"\bWARN\b"#, color: palette.warn, options: [.caseInsensitive])
            paint(#"\bERROR\b"#, color: palette.error, options: [.caseInsensitive])

            if let componentRegex = try? NSRegularExpression(pattern: #"\[([^\]/\]]+)\]"#) {
                for match in componentRegex.matches(in: line, range: fullRange) where match.range.length > 2 {
                    let inner = ns.substring(with: NSRange(location: match.range.location + 1, length: match.range.length - 2))
                    if inner.range(of: #"^\d{2}[:.]\d{2}[:.]\d{2}(\s+(INFO|WARN|ERROR)(/(INFO|WARN|ERROR))?)?$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                        continue
                    }
                    if inner.range(of: #"^\d{1,2}\s*\d{1,2}月\d{4}\s+\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?$"#, options: [.regularExpression]) != nil {
                        continue
                    }
                    let innerRange = NSRange(location: match.range.location + 1, length: match.range.length - 2)
                    attributed.addAttribute(.foregroundColor, value: palette.component, range: innerRange)
                }
            }
            return attributed
        }
    }
}

private struct ConsoleHighlightPalette {
    let timestamp: NSColor
    let info: NSColor
    let warn: NSColor
    let error: NSColor
    let component: NSColor

    init(style: HighlightStyle) {
        switch style {
        case .system:
            timestamp = .systemBlue
            info = .systemGreen
            warn = .systemYellow
            error = .systemRed
            component = .systemPurple
        case .vivid:
            timestamp = .systemCyan
            info = .systemGreen
            warn = .systemOrange
            error = .systemRed
            component = .systemPink
        }
    }
}

private extension ConsoleFontStyle {
    func toFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        switch self {
        case .system:
            return NSFont.systemFont(ofSize: size, weight: weight)
        case .monospaced:
            return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
    }
}

extension ServerConsoleView {
    private func scheduleStopStatusCheck() {
        Task {
            for _ in 0..<16 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if ServerProcessManager.shared.isServerRunning(serverId: server.id) == false,
                   LocalServerDirectService.isDirectModeAvailable(server: server) == false {
                    await MainActor.run {
                        ServerStatusManager.shared.setServerRunning(serverId: server.id, isRunning: false)
                        ServerConsoleManager.shared.detach(serverId: server.id)
                    }
                    break
                }
            }
        }
    }

    private func clearConsole() {
        console.clear(serverId: server.id)
        lastLocalPolledText = currentLocalLogSnapshot(serverName: server.directoryName)
        if isRemoteServer, let node = resolvedRemoteNode(nodeId: server.nodeId) {
            Task { @MainActor in
                if let snapshot = try? await SSHNodeService.fetchRemoteServerLog(node: node, serverName: server.name) {
                    lastRemotePolledText = filterNoisyRconLifecycleLogs(snapshot).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    lastRemotePolledText = ""
                }
            }
        } else {
            lastRemotePolledText = ""
        }
    }
}
// swiftlint:enable file_length
