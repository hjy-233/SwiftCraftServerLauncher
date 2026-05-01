import Foundation
import Combine

struct ServerSchedule: Identifiable, Codable, Hashable {
    enum Trigger: String, Codable, CaseIterable {
        case time
        case consoleKeyword

        var i18nKey: String {
            switch self {
            case .time:
                return "server.schedules.trigger.time"
            case .consoleKeyword:
                return "server.schedules.trigger.console"
            }
        }
    }

    enum Action: String, Codable, CaseIterable {
        case start
        case stop
        case restart
        case command

        var i18nKey: String {
            switch self {
            case .start:
                return "server.schedules.action.start"
            case .stop:
                return "server.schedules.action.stop"
            case .restart:
                return "server.schedules.action.restart"
            case .command:
                return "server.schedules.action.command"
            }
        }
    }

    struct Time: Codable, Hashable {
        var hour: Int
        var minute: Int
    }

    var id: UUID
    var name: String
    var isEnabled: Bool
    var trigger: Trigger
    var action: Action
    var time: Time
    var weekdays: [Int]
    var command: String
    var keyword: String
    var keywordIgnoreCase: Bool
    var keywordIsRegex: Bool

    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        trigger: Trigger = .time,
        action: Action,
        time: Time,
        weekdays: [Int] = [],
        command: String = "",
        keyword: String = "",
        keywordIgnoreCase: Bool = true,
        keywordIsRegex: Bool = false
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.trigger = trigger
        self.action = action
        self.time = time
        self.weekdays = weekdays
        self.command = command
        self.keyword = keyword
        self.keywordIgnoreCase = keywordIgnoreCase
        self.keywordIsRegex = keywordIsRegex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        trigger = try container.decodeIfPresent(Trigger.self, forKey: .trigger) ?? .time
        action = try container.decode(Action.self, forKey: .action)
        time = try container.decodeIfPresent(Time.self, forKey: .time) ?? .init(hour: 0, minute: 0)
        weekdays = try container.decodeIfPresent([Int].self, forKey: .weekdays) ?? []
        command = try container.decodeIfPresent(String.self, forKey: .command) ?? ""
        keyword = try container.decodeIfPresent(String.self, forKey: .keyword) ?? ""
        keywordIgnoreCase = try container.decodeIfPresent(Bool.self, forKey: .keywordIgnoreCase) ?? true
        keywordIsRegex = try container.decodeIfPresent(Bool.self, forKey: .keywordIsRegex) ?? false
    }
}

@MainActor
final class ServerScheduleService: ObservableObject {
    static let shared = ServerScheduleService()

    private var schedulesByServerId: [String: [ServerSchedule]] = [:]
    private var serversById: [String: ServerInstance] = [:]
    private var lastFireToken: [UUID: String] = [:]
    private var lastRunAt: [UUID: Date] = [:]
    private var timer: Timer?
    private var nodeRepository: ServerNodeRepository?
    private var consoleCancellable: AnyCancellable?
    private var lastConsoleSequence: [UUID: Int] = [:]
    private var lastConsoleEcho: [UUID: (command: String, time: Date)] = [:]
    private var consoleLineBuffer: [String: String] = [:]
    private var lastConsoleTrigger: [UUID: (line: String, command: String, time: Date)] = [:]
    private var consolePollTasks: [String: Task<Void, Never>] = [:]
    private var lastLocalPolledText: [String: String] = [:]
    private var lastRemotePolledText: [String: String] = [:]

    private init() {}

    func attach(nodeRepository: ServerNodeRepository) {
        self.nodeRepository = nodeRepository
        subscribeConsole()
    }

    func refreshServers(_ servers: [ServerInstance]) {
        serversById = Dictionary(uniqueKeysWithValues: servers.map { ($0.id, $0) })
        for server in servers where schedulesByServerId[server.id] == nil {
            schedulesByServerId[server.id] = []
            loadSchedulesAsyncIfNeeded(server: server)
        }
        startTimerIfNeeded()
        refreshConsolePolling()
    }

    func schedules(for server: ServerInstance) -> [ServerSchedule] {
        if let existing = schedulesByServerId[server.id] {
            loadSchedulesAsyncIfNeeded(server: server)
            return existing
        }
        schedulesByServerId[server.id] = []
        loadSchedulesAsyncIfNeeded(server: server)
        return []
    }

    func updateSchedules(for server: ServerInstance, schedules: [ServerSchedule]) {
        schedulesByServerId[server.id] = schedules
        serversById[server.id] = server
        saveSchedules(server: server, schedules: schedules)
        startTimerIfNeeded()
        tick()
        refreshConsolePolling()
        NotificationCenter.default.post(name: .serverSchedulesDidChange, object: server.id)
    }

    func loadSchedules(server: ServerInstance) -> [ServerSchedule] {
        if server.nodeId == ServerNode.local.id {
            return schedulesByServerId[server.id] ?? []
        }
        let url = scheduleFileURL(for: server)
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        return (try? JSONDecoder().decode([ServerSchedule].self, from: data)) ?? []
    }

    private func saveSchedules(server: ServerInstance, schedules: [ServerSchedule]) {
        if server.nodeId == ServerNode.local.id {
            Task {
                do {
                    try await ServerScheduleCoreService.writeSchedules(server: server, schedules: schedules)
                } catch {
                    await MainActor.run { GlobalErrorHandler.shared.handle(error) }
                }
            }
            return
        }
        let url = scheduleFileURL(for: server)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(schedules) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func scheduleFileURL(for server: ServerInstance) -> URL {
        let base: URL
        if server.nodeId == ServerNode.local.id {
            base = AppPaths.serverDirectory(serverName: server.directoryName)
        } else {
            base = AppPaths.remoteNodeServersDirectory(nodeId: server.nodeId)
                .appendingPathComponent(server.name, isDirectory: true)
        }
        return base.appendingPathComponent(".scsl", isDirectory: true)
            .appendingPathComponent("schedules.json")
    }

    private func loadSchedulesAsyncIfNeeded(server: ServerInstance) {
        if server.nodeId != ServerNode.local.id {
            let loaded = loadSchedules(server: server)
            if schedulesByServerId[server.id] != loaded {
                schedulesByServerId[server.id] = loaded
                NotificationCenter.default.post(name: .serverSchedulesDidChange, object: server.id)
            }
            return
        }

        Task {
            do {
                let loaded = try await ServerScheduleCoreService.readSchedules(server: server)
                guard serversById[server.id] != nil else { return }
                if schedulesByServerId[server.id] != loaded {
                    schedulesByServerId[server.id] = loaded
                    NotificationCenter.default.post(name: .serverSchedulesDidChange, object: server.id)
                    refreshConsolePolling()
                }
            } catch {
                GlobalErrorHandler.shared.handle(error)
            }
        }
    }

    private func startTimerIfNeeded() {
        if timer != nil { return }
        timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func refreshConsolePolling() {
        let activeServerIds = Set(schedulesByServerId.compactMap { serverId, schedules -> String? in
            let hasConsole = schedules.contains { $0.isEnabled && $0.trigger == .consoleKeyword }
            if hasConsole {
                return serverId
            }
            return nil
        })

        for (serverId, task) in consolePollTasks where !activeServerIds.contains(serverId) {
            task.cancel()
            consolePollTasks.removeValue(forKey: serverId)
            lastLocalPolledText.removeValue(forKey: serverId)
            lastRemotePolledText.removeValue(forKey: serverId)
        }

        for serverId in activeServerIds where consolePollTasks[serverId] == nil {
            consolePollTasks[serverId] = Task.detached(priority: .background) { [weak self] in
                while !Task.isCancelled {
                    await self?.pollConsole(for: serverId)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
    }

    private func pollConsole(for serverId: String) async {
        guard let server = serversById[serverId] else { return }
        if server.nodeId == ServerNode.local.id {
            await pollLocalLog(server: server)
        } else {
            await pollRemoteLog(server: server)
        }
    }

    private func pollLocalLog(server: ServerInstance) async {
        let serverDir = AppPaths.serverDirectory(serverName: server.directoryName)
        let candidates = [
            serverDir.appendingPathComponent("logs/latest.log"),
            serverDir.appendingPathComponent("latest.log"),
            serverDir.appendingPathComponent("scsl-server.log"),
            serverDir.appendingPathComponent("server.log"),
        ]
        for file in candidates where FileManager.default.fileExists(atPath: file.path) {
            if let text = try? String(contentsOf: file, encoding: .utf8), !text.isEmpty {
                let current = text.components(separatedBy: .newlines).suffix(300).joined(separator: "\n")
                let previous = lastLocalPolledText[server.id] ?? ""
                let delta = incrementalDelta(previous: previous, current: current)
                if !delta.isEmpty {
                    ServerConsoleManager.shared.appendExternal(serverId: server.id, text: delta + "\n")
                    lastLocalPolledText[server.id] = current
                } else {
                    lastLocalPolledText[server.id] = current
                }
                return
            }
        }
    }

    private func pollRemoteLog(server: ServerInstance) async {
        guard let node = nodeRepository?.getNode(by: server.nodeId) else { return }
        do {
            let text = try await SSHNodeService.fetchRemoteServerLog(node: node, serverName: server.name)
            let filtered = filterNoisyRconLifecycleLogs(text)
            let current = filtered.trimmingCharacters(in: .whitespacesAndNewlines)
            if current.isEmpty { return }
            let previous = lastRemotePolledText[server.id] ?? ""
            let delta = incrementalDelta(previous: previous, current: current)
            if !delta.isEmpty {
                ServerConsoleManager.shared.appendExternal(serverId: server.id, text: delta + "\n")
                lastRemotePolledText[server.id] = current
            } else {
                lastRemotePolledText[server.id] = current
            }
        } catch {
            return
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

    private func tick() {
        let now = Date()
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month, .day, .weekday, .hour, .minute], from: now)
        for (serverId, schedules) in schedulesByServerId {
            guard let server = serversById[serverId] else { continue }
            for schedule in schedules where schedule.isEnabled {
                guard schedule.trigger == .time else { continue }
                if shouldFire(schedule, components: comps, now: now, calendar: calendar),
                   !hasFired(schedule, components: comps) {
                    markFired(schedule, components: comps)
                    Task { @MainActor in
                        await execute(schedule: schedule, server: server, reason: "timer")
                    }
                }
            }
        }
    }

    private func subscribeConsole() {
        if consoleCancellable != nil { return }
        consoleCancellable = ServerConsoleManager.shared.$latestEvent
            .compactMap { $0 }
            .sink { [weak self] event in
                guard let self else { return }
                self.handleConsoleEvent(event)
            }
    }

    private func handleConsoleEvent(_ event: ServerConsoleManager.ConsoleEvent) {
        guard event.kind == .append else { return }
        guard let server = serversById[event.serverId] else { return }
        guard let schedules = schedulesByServerId[event.serverId], schedules.isEmpty == false else { return }
        let lines = consumeConsoleLines(serverId: event.serverId, chunk: event.text)

        for line in lines {
            let sanitized = sanitizeConsoleLine(line)
            let message = extractServerMessage(from: sanitized)
            for schedule in schedules where schedule.isEnabled && schedule.trigger == .consoleKeyword {
                if let echo = lastConsoleEcho[schedule.id] {
                    let age = Date().timeIntervalSince(echo.time)
                    if age < 2.0 {
                        let current: String
                        let last: String
                        if schedule.keywordIgnoreCase {
                            current = message.lowercased()
                            last = echo.command.lowercased()
                        } else {
                            current = message
                            last = echo.command
                        }
                        if current == last {
                            continue
                        }
                    }
                }
                if let guardInfo = lastConsoleTrigger[schedule.id] {
                    let age = Date().timeIntervalSince(guardInfo.time)
                    if age < 2.0 {
                        let currentLine: String
                        let lastLine: String
                        let lastCommand: String
                        if schedule.keywordIgnoreCase {
                            currentLine = message.lowercased()
                            lastLine = guardInfo.line.lowercased()
                            lastCommand = guardInfo.command.lowercased()
                        } else {
                            currentLine = message
                            lastLine = guardInfo.line
                            lastCommand = guardInfo.command
                        }
                        if currentLine == lastLine || currentLine.contains(lastCommand) {
                            continue
                        }
                    }
                }
                let lastSeq = lastConsoleSequence[schedule.id]
                if lastSeq == event.sequence { continue }
                let keyword = schedule.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
                if keyword.isEmpty { continue }
                if schedule.keywordIsRegex {
                    guard let match = matchRegex(
                        keyword,
                        in: message,
                        ignoreCase: schedule.keywordIgnoreCase
                    ) else { continue }
                    lastConsoleSequence[schedule.id] = event.sequence
                    Task {
                        await execute(
                            schedule: schedule,
                            server: server,
                            reason: "console",
                            context: .init(line: message, rawLine: sanitized, match: match)
                        )
                    }
                    continue
                }
                let haystack: String
                let needle: String
                if schedule.keywordIgnoreCase {
                    haystack = message.lowercased()
                    needle = keyword.lowercased()
                } else {
                    haystack = message
                    needle = keyword
                }
                guard haystack.contains(needle) else { continue }
                lastConsoleSequence[schedule.id] = event.sequence
                Task {
                    await execute(
                        schedule: schedule,
                        server: server,
                        reason: "console",
                        context: .init(line: message, rawLine: sanitized, match: nil)
                    )
                }
            }
        }
    }

    private func consumeConsoleLines(serverId: String, chunk: String) -> [String] {
        var buffer = consoleLineBuffer[serverId] ?? ""
        buffer.append(chunk)
        var lines: [String] = []
        var current = ""
        for scalar in buffer.unicodeScalars {
            if scalar == "\n" || scalar == "\r" {
                if current.isEmpty == false {
                    lines.append(current)
                    current = ""
                }
                continue
            }
            current.unicodeScalars.append(scalar)
        }
        consoleLineBuffer[serverId] = current
        return lines
    }

    private func shouldFire(
        _ schedule: ServerSchedule,
        components: DateComponents,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard let hour = components.hour, let minute = components.minute else { return false }
        if schedule.weekdays.isEmpty == false {
            guard let weekday = components.weekday, schedule.weekdays.contains(weekday) else { return false }
        }
        guard hour == schedule.time.hour, minute == schedule.time.minute else {
            // allow late firing if app was suspended: within 2 minutes after target time
            let today = calendar.dateComponents([.year, .month, .day], from: now)
            var target = DateComponents()
            target.year = today.year
            target.month = today.month
            target.day = today.day
            target.hour = schedule.time.hour
            target.minute = schedule.time.minute
            guard let fireDate = calendar.date(from: target) else { return false }
            if now >= fireDate && now.timeIntervalSince(fireDate) <= 120 {
                return true
            }
            return false
        }
        return true
    }

    private func token(for components: DateComponents, scheduleId: UUID) -> String {
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return "\(scheduleId.uuidString)-\(year)-\(month)-\(day)-\(hour)-\(minute)"
    }

    private func hasFired(_ schedule: ServerSchedule, components: DateComponents) -> Bool {
        lastFireToken[schedule.id] == token(for: components, scheduleId: schedule.id)
    }

    private func markFired(_ schedule: ServerSchedule, components: DateComponents) {
        lastFireToken[schedule.id] = token(for: components, scheduleId: schedule.id)
    }

    func runNow(schedule: ServerSchedule, server: ServerInstance) async {
        await execute(schedule: schedule, server: server, reason: "manual")
    }

    private struct TriggerContext {
        let line: String
        let rawLine: String
        let match: NSTextCheckingResult?
    }

    private func execute(
        schedule: ServerSchedule,
        server: ServerInstance,
        reason: String,
        context: TriggerContext? = nil
    ) async {
        Logger.shared.info("定时任务触发(\(reason)): \(server.name) / \(schedule.name) / \(schedule.action.rawValue)")
        if server.nodeId == ServerNode.local.id {
            let didRun = await executeLocalScheduleWithCLI(schedule: schedule, server: server, context: context)
            guard didRun else { return }
            lastRunAt[schedule.id] = Date()
            NotificationCenter.default.post(name: .serverScheduleDidRun, object: schedule.id)
            return
        }

        let useCase = ServerLaunchUseCase()
        switch schedule.action {
        case .start:
            await useCase.launchServer(server: server)
        case .stop:
            await useCase.stopServer(server: server)
        case .restart:
            await useCase.stopServer(server: server)
            await useCase.launchServer(server: server)
        case .command:
            var command = schedule.command
            if schedule.trigger == .consoleKeyword, let context {
                command = substituteRegexTokens(
                    in: command,
                    line: context.line,
                    rawLine: context.rawLine,
                    match: context.match,
                    ignoreCase: schedule.keywordIgnoreCase
                )
                lastConsoleEcho[schedule.id] = (command: command, time: Date())
                lastConsoleTrigger[schedule.id] = (line: context.line, command: command, time: Date())
            }
            command = command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty else { return }
            if let guardInfo = lastConsoleTrigger[schedule.id] {
                if Date().timeIntervalSince(guardInfo.time) < 1.0 {
                    return
                }
            }
            do {
                if server.nodeId == ServerNode.local.id {
                    _ = try await Task.detached(priority: .userInitiated) {
                        try await LocalServerDirectService.sendCommand(server: server, command: command)
                    }.value
                } else if let node = nodeRepository?.getNode(by: server.nodeId) {
                    try await SSHNodeService.sendRemoteDirectCommand(
                        node: node,
                        serverName: server.name,
                        command: command
                    )
                }
            } catch {
                Logger.shared.error("定时任务命令执行失败: \(error.localizedDescription)")
                GlobalErrorHandler.shared.handle(error)
            }
        }
        lastRunAt[schedule.id] = Date()
        NotificationCenter.default.post(name: .serverScheduleDidRun, object: schedule.id)
    }

    private func executeLocalScheduleWithCLI(
        schedule: ServerSchedule,
        server: ServerInstance,
        context: TriggerContext?
    ) async -> Bool {
        do {
            switch schedule.action {
            case .start:
                _ = try await ScslCoreCLIService.shared.run(arguments: ["server", "start", server.id])
                return true
            case .stop:
                _ = try await ScslCoreCLIService.shared.run(arguments: ["server", "stop", server.id])
                return true
            case .restart:
                _ = try await ScslCoreCLIService.shared.run(arguments: ["server", "restart", server.id])
                return true
            case .command:
                let command = buildScheduledCommand(schedule: schedule, context: context)
                guard !command.isEmpty else { return false }
                _ = try await ScslCoreCLIService.shared.run(arguments: ["server", "send", server.id, command])
                return true
            }
        } catch {
            Logger.shared.error("本地定时任务执行失败: \(error.localizedDescription)")
            GlobalErrorHandler.shared.handle(error)
            return false
        }
    }

    private func buildScheduledCommand(
        schedule: ServerSchedule,
        context: TriggerContext?
    ) -> String {
        var command = schedule.command
        if schedule.trigger == .consoleKeyword, let context {
            command = substituteRegexTokens(
                in: command,
                line: context.line,
                rawLine: context.rawLine,
                match: context.match,
                ignoreCase: schedule.keywordIgnoreCase
            )
            lastConsoleEcho[schedule.id] = (command: command, time: Date())
            lastConsoleTrigger[schedule.id] = (line: context.line, command: command, time: Date())
        }
        command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return "" }
        if let guardInfo = lastConsoleTrigger[schedule.id],
           Date().timeIntervalSince(guardInfo.time) < 1.0 {
            return ""
        }
        return command
    }

    func lastRunDate(for schedule: ServerSchedule) -> Date? {
        lastRunAt[schedule.id]
    }
}

extension Notification.Name {
    static let serverScheduleDidRun = Notification.Name("scsl.server.schedule.didRun")
    static let serverSchedulesDidChange = Notification.Name("scsl.server.schedules.didChange")
}

private func sanitizeConsoleLine(_ line: String) -> String {
    let pattern = #"\u001B\[[0-9;]*[A-Za-z]"#
    if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.stringByReplacingMatches(in: line, options: [], range: range, withTemplate: "")
    }
    return line
}

private func matchRegex(
    _ pattern: String,
    in text: String,
    ignoreCase: Bool
) -> NSTextCheckingResult? {
    let options: NSRegularExpression.Options
    if ignoreCase {
        options = [.caseInsensitive]
    } else {
        options = []
    }
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
        return nil
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.firstMatch(in: text, options: [], range: range)
}

private func substituteRegexTokens(
    in template: String,
    line: String,
    rawLine: String,
    match: NSTextCheckingResult?,
    ignoreCase: Bool
) -> String {
    var result = template
    if result.contains("{{line}}") || result.contains("{{raw}}") || result.contains("{{rawLine}}") {
        result = result.replacingOccurrences(of: "{{line}}", with: line)
        result = result.replacingOccurrences(of: "{{raw}}", with: rawLine)
        result = result.replacingOccurrences(of: "{{rawLine}}", with: rawLine)
    }
    let pattern = #"\{\{([^}]+)\}\}"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        return result
    }
    let nsTemplate = result as NSString
    let range = NSRange(location: 0, length: nsTemplate.length)
    let matches = regex.matches(in: result, options: [], range: range).reversed()
    for item in matches {
        guard item.numberOfRanges > 1,
              let tokenRange = Range(item.range(at: 1), in: result),
              let fullRange = Range(item.range(at: 0), in: result) else { continue }
        let token = String(result[tokenRange])
        let replacement: String
        if token == "line" {
            replacement = line
        } else if token == "raw" || token == "rawLine" {
            replacement = rawLine
        } else if token == "0" {
            replacement = substring(for: match, group: 0, in: line) ?? ""
        } else if let index = Int(token) {
            replacement = substring(for: match, group: index, in: line) ?? ""
        } else if let (pattern, group) = parseInlineRegexToken(token) {
            if let inlineMatch = matchRegex(pattern, in: line, ignoreCase: ignoreCase) {
                replacement = substring(for: inlineMatch, group: group, in: line) ?? ""
            } else {
                replacement = ""
            }
        } else {
            replacement = ""
        }
        result.replaceSubrange(fullRange, with: replacement)
    }
    return result
}

private func extractServerMessage(from line: String) -> String {
    let patterns = [
        "] [Server] ",
        "] [Server]: ",
        "[Server] ",
        "[Server]: ",
    ]
    for token in patterns {
        if let range = line.range(of: token, options: .backwards) {
            let message = line[range.upperBound...]
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                return trimmed
            }
        }
    }
    return line.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func parseInlineRegexToken(_ token: String) -> (String, Int)? {
    if token.hasPrefix("re:") {
        let raw = String(token.dropFirst(3))
        return parseInlineRegexPayload(raw)
    }
    if token.hasPrefix("/") {
        return parseInlineRegexPayload(token)
    }
    return nil
}

private func parseInlineRegexPayload(_ raw: String) -> (String, Int)? {
    var pattern = raw
    var group = 0
    if let pipeIndex = raw.lastIndex(of: "|") {
        let groupText = raw[raw.index(after: pipeIndex)...]
        if let parsed = Int(groupText) {
            pattern = String(raw[..<pipeIndex])
            group = parsed
        }
    }
    if pattern.hasPrefix("/") && pattern.hasSuffix("/") && pattern.count >= 2 {
        pattern = String(pattern.dropFirst().dropLast())
    }
    if pattern.isEmpty { return nil }
    return (pattern, group)
}

private func substring(
    for match: NSTextCheckingResult?,
    group: Int,
    in text: String
) -> String? {
    guard let match, group < match.numberOfRanges else { return nil }
    let range = match.range(at: group)
    guard let swiftRange = Range(range, in: text) else { return nil }
    return String(text[swiftRange])
}
