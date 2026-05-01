import SwiftUI

struct ServerSchedulesView: View {
    let server: ServerInstance
    @StateObject private var store: ServerScheduleStore
    @State private var editingSchedule: ServerSchedule?
    @State private var isCreatingNew = false

    init(server: ServerInstance) {
        self.server = server
        _store = StateObject(wrappedValue: ServerScheduleStore(server: server))
    }

    var body: some View {
        ServerDetailPage(title: "server.schedules.title".localized()) {
            VStack(alignment: .leading, spacing: 16) {
                headerBar
                if store.schedules.isEmpty {
                    ServerDetailEmptyState(text: "server.schedules.empty".localized())
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(store.schedules) { schedule in
                                scheduleRow(schedule)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .onAppear { store.reload(server: server) }
        .onChange(of: server.id) { _, _ in
            store.reload(server: server)
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverDetailToolbarAction)) { notification in
            guard let action = ServerDetailToolbarActionBus.action(from: notification),
                  action == .schedulesNew else { return }
            startCreate()
        }
        .sheet(item: $editingSchedule) { schedule in
            ServerScheduleEditor(
                schedule: schedule,
                isNew: isCreatingNew,
                serverName: server.name,
                onSave: { updated in
                    if isCreatingNew {
                        store.addNew(updated)
                    } else {
                        store.upsert(updated)
                    }
                    editingSchedule = nil
                    isCreatingNew = false
                },
                onCancel: {
                    editingSchedule = nil
                    isCreatingNew = false
                }
            )
        }
    }

    private var headerBar: some View {
        HStack {
            Text("server.schedules.subtitle".localized())
                .font(.headline)
            Spacer()
        }
    }

    private func startCreate() {
        let draft = ServerSchedule(
            name: "server.schedules.default_name".localized(),
            trigger: .time,
            action: .start,
            time: .init(hour: 2, minute: 0)
        )
        isCreatingNew = true
        editingSchedule = draft
    }

    private func scheduleRow(_ schedule: ServerSchedule) -> some View {
        _ = store.lastRunToken
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(schedule.name)
                    .font(.headline)
                Text(scheduleSummary(schedule))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let nextRun = store.nextRunText(for: schedule) {
                    Text("\("server.schedules.next_run".localized()) \(nextRun)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let lastRun = store.lastRunText(for: schedule) {
                    Text("\("server.schedules.last_run".localized()) \(lastRun)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Button("server.schedules.run_now".localized()) {
                    Task { @MainActor in
                        await store.runNow(schedule)
                    }
                }
                .buttonStyle(.bordered)
                Toggle("", isOn: bindingForSchedule(schedule))
                    .labelsHidden()
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.windowBackgroundColor).opacity(0.3))
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button("server.schedules.edit".localized()) {
                isCreatingNew = false
                editingSchedule = schedule
            }
            Button("server.schedules.delete".localized(), role: .destructive) {
                store.delete(schedule)
            }
        }
        .onTapGesture {
            isCreatingNew = false
            editingSchedule = schedule
        }
    }

    private func scheduleSummary(_ schedule: ServerSchedule) -> String {
        let timeText = String(format: "%02d:%02d", schedule.time.hour, schedule.time.minute)
        let actionText = schedule.action.i18nKey.localized()
        let daysText = scheduleDaysText(schedule.weekdays)
        if schedule.trigger == .consoleKeyword {
            let keyword = schedule.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            if keyword.isEmpty {
                return "\(actionText) · \("server.schedules.trigger.console".localized())"
            }
            if schedule.keywordIsRegex {
                return "\(actionText) · /\(keyword)/"
            }
            return "\(actionText) · \(keyword)"
        }
        if schedule.action == .command {
            return "\(actionText) · \(timeText) · \(daysText)"
        }
        return "\(actionText) · \(timeText) · \(daysText)"
    }

    private func scheduleDaysText(_ weekdays: [Int]) -> String {
        if weekdays.isEmpty {
            return "server.schedules.days.everyday".localized()
        }
        let ordered = weekdays.sorted()
        let labels = ordered.map { weekdayLabel($0) }
        return labels.joined(separator: " ")
    }

    private func weekdayLabel(_ weekday: Int) -> String {
        switch weekday {
        case 1: return "server.schedules.weekday.sun".localized()
        case 2: return "server.schedules.weekday.mon".localized()
        case 3: return "server.schedules.weekday.tue".localized()
        case 4: return "server.schedules.weekday.wed".localized()
        case 5: return "server.schedules.weekday.thu".localized()
        case 6: return "server.schedules.weekday.fri".localized()
        case 7: return "server.schedules.weekday.sat".localized()
        default: return ""
        }
    }

    private func bindingForSchedule(_ schedule: ServerSchedule) -> Binding<Bool> {
        Binding(
            get: { schedule.isEnabled },
            set: { newValue in
                var updated = schedule
                updated.isEnabled = newValue
                store.upsert(updated)
            }
        )
    }
}

@MainActor
final class ServerScheduleStore: ObservableObject {
    @Published var schedules: [ServerSchedule] = []
    @Published var lastRunToken = UUID()
    private var server: ServerInstance
    private var runObserver: NSObjectProtocol?
    private var schedulesObserver: NSObjectProtocol?

    init(server: ServerInstance) {
        self.server = server
        reload(server: server)
        runObserver = NotificationCenter.default.addObserver(
            forName: .serverScheduleDidRun,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.lastRunToken = UUID()
            }
        }
        schedulesObserver = NotificationCenter.default.addObserver(
            forName: .serverSchedulesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let serverId = notification.object as? String,
                  serverId == self.server.id else { return }
            self.schedules = ServerScheduleService.shared.schedules(for: self.server)
        }
    }

    deinit {
        if let runObserver {
            NotificationCenter.default.removeObserver(runObserver)
        }
        if let schedulesObserver {
            NotificationCenter.default.removeObserver(schedulesObserver)
        }
    }

    func reload(server: ServerInstance) {
        self.server = server
        schedules = ServerScheduleService.shared.schedules(for: server)
    }

    func upsert(_ schedule: ServerSchedule) {
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[index] = schedule
        } else {
            schedules.insert(schedule, at: 0)
        }
        persist()
    }

    func addNew(_ schedule: ServerSchedule) {
        var draft = schedule
        if schedules.contains(where: { $0.id == draft.id }) {
            draft.id = UUID()
        }
        schedules.insert(draft, at: 0)
        persist()
    }

    func delete(_ schedule: ServerSchedule) {
        schedules.removeAll { $0.id == schedule.id }
        persist()
    }

    private func persist() {
        ServerScheduleService.shared.updateSchedules(for: server, schedules: schedules)
    }

    func lastRunText(for schedule: ServerSchedule) -> String? {
        guard let date = ServerScheduleService.shared.lastRunDate(for: schedule) else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    func nextRunText(for schedule: ServerSchedule) -> String? {
        guard let date = nextRunDate(for: schedule) else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    func runNow(_ schedule: ServerSchedule) async {
        await ServerScheduleService.shared.runNow(schedule: schedule, server: server)
        lastRunToken = UUID()
    }

    private func nextRunDate(for schedule: ServerSchedule) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        let baseComponents = calendar.dateComponents([.year, .month, .day], from: now)
        for offset in 0..<8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.date(from: baseComponents) ?? now) else {
                continue
            }
            let weekday = calendar.component(.weekday, from: day)
            if schedule.weekdays.isEmpty == false, !schedule.weekdays.contains(weekday) {
                continue
            }
            var comps = calendar.dateComponents([.year, .month, .day], from: day)
            comps.hour = schedule.time.hour
            comps.minute = schedule.time.minute
            if let candidate = calendar.date(from: comps), candidate >= now {
                return candidate
            }
        }
        return nil
    }
}

struct ServerScheduleEditor: View {
    @State private var draft: ServerSchedule
    @State private var time: Date
    let isNew: Bool
    let serverName: String
    let onSave: (ServerSchedule) -> Void
    let onCancel: () -> Void
    @State private var showAISidebar = true

    init(
        schedule: ServerSchedule,
        isNew: Bool,
        serverName: String,
        onSave: @escaping (ServerSchedule) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: schedule)
        let base = Calendar.current.date(from: DateComponents(hour: schedule.time.hour, minute: schedule.time.minute))
        _time = State(initialValue: base ?? Date())
        self.isNew = isNew
        self.serverName = serverName
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        CommonSheetView {
            HStack {
                Text(isNew ? "server.schedules.create".localized() : "server.schedules.edit".localized())
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    showAISidebar.toggle()
                } label: {
                    Label(
                        "server.schedules.ai_helper.button".localized(),
                        systemImage: "sparkles"
                    )
                }
                .buttonStyle(.bordered)
            }
        } body: {
            HStack(spacing: 12) {
                if showAISidebar {
                    AIScheduleAssistantPanel(
                        serverName: serverName,
                        draft: $draft,
                        time: $time
                    )
                    .frame(width: 260)
                }
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("server.schedules.name".localized()) {
                        TextField("", text: $draft.name)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("server.schedules.action".localized()) {
                        Picker("", selection: $draft.action) {
                            ForEach(ServerSchedule.Action.allCases, id: \.self) { action in
                                Text(action.i18nKey.localized()).tag(action)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    LabeledContent("server.schedules.trigger.type".localized()) {
                        Picker("", selection: $draft.trigger) {
                            ForEach(ServerSchedule.Trigger.allCases, id: \.self) { trigger in
                                Text(trigger.i18nKey.localized()).tag(trigger)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    if draft.action == .command {
                        LabeledContent("server.schedules.command".localized()) {
                            TextField("server.schedules.command.placeholder".localized(), text: $draft.command)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    if draft.trigger == .time {
                        LabeledContent("server.schedules.time".localized()) {
                            DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                        LabeledContent("server.schedules.days".localized()) {
                            WeekdaySelector(selected: $draft.weekdays)
                        }
                    } else {
                        LabeledContent("server.schedules.trigger.keyword".localized()) {
                            TextField("server.schedules.trigger.keyword.placeholder".localized(), text: $draft.keyword)
                                .textFieldStyle(.roundedBorder)
                        }
                        Toggle(
                            "server.schedules.trigger.regex".localized(),
                            isOn: $draft.keywordIsRegex
                        )
                        Toggle(
                            "server.schedules.trigger.ignore_case".localized(),
                            isOn: $draft.keywordIgnoreCase
                        )
                        Text("server.schedules.trigger.regex.hint".localized())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("server.schedules.enabled".localized(), isOn: $draft.isEnabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } footer: {
            HStack {
                Spacer()
                Button("common.cancel".localized()) { onCancel() }
                Button("common.confirm".localized()) { commit() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(width: 780)
    }

    private func commit() {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
        draft.time = .init(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.name = "server.schedules.default_name".localized()
        }
        onSave(draft)
    }
}

struct WeekdaySelector: View {
    @Binding var selected: [Int]

    var body: some View {
        HStack(spacing: 6) {
            weekdayButton(2, "server.schedules.weekday.mon".localized())
            weekdayButton(3, "server.schedules.weekday.tue".localized())
            weekdayButton(4, "server.schedules.weekday.wed".localized())
            weekdayButton(5, "server.schedules.weekday.thu".localized())
            weekdayButton(6, "server.schedules.weekday.fri".localized())
            weekdayButton(7, "server.schedules.weekday.sat".localized())
            weekdayButton(1, "server.schedules.weekday.sun".localized())
        }
    }

    private func weekdayButton(_ value: Int, _ label: String) -> some View {
        let isSelected = selected.contains(value)
        return Button {
            if isSelected {
                selected.removeAll { $0 == value }
            } else {
                selected.append(value)
            }
        } label: {
            Text(label)
                .font(.subheadline)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.2))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct AIScheduleAssistantPanel: View {
    let serverName: String
    @Binding var draft: ServerSchedule
    @Binding var time: Date

    @State private var userPrompt = ""
    @StateObject private var chatState = ChatState()
    @State private var isGenerating = false
    @State private var parsedSuggestion: AIScheduleFormSuggestion?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("server.schedules.ai_helper.title".localized())
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("server.schedules.ai_helper.hint".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $userPrompt)
                .font(.system(.body))
                .frame(height: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.3))
                )
            Button {
                generate()
            } label: {
                Label("server.schedules.ai_helper.generate".localized(), systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGenerating)
        }
        .onChange(of: chatState.messages) { _, _ in
            parseSuggestion()
        }
    }

    private var latestResponse: String? {
        chatState.messages.last { $0.role == .assistant }?.content
    }

    private func generate() {
        let goal = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = buildPrompt(userGoal: goal)
        chatState.clear()
        isGenerating = true
        Task { @MainActor in
            await AIChatManager.shared.sendMessage(prompt, chatState: chatState)
            isGenerating = false
        }
    }

    private func parseSuggestion() {
        guard let response = latestResponse else { return }
        parsedSuggestion = parseSuggestion(from: response)
        applySuggestion()
    }

    private func applySuggestion() {
        guard let suggestion = parsedSuggestion else { return }
        if let name = suggestion.name, !name.isEmpty {
            draft.name = name
        }
        if let actionValue = suggestion.action,
           let action = ServerSchedule.Action.fromString(actionValue) {
            draft.action = action
        }
        if let triggerValue = suggestion.trigger,
           let trigger = ServerSchedule.Trigger.fromString(triggerValue) {
            draft.trigger = trigger
        }
        if let keyword = suggestion.keyword {
            draft.keyword = keyword
        }
        if let command = suggestion.command {
            draft.command = command
        }
        draft.keywordIsRegex = suggestion.useRegex
        draft.keywordIgnoreCase = suggestion.ignoreCase
        if let weekdays = suggestion.weekdays, !weekdays.isEmpty {
            draft.weekdays = weekdays
        }
        if let timeValue = suggestion.time,
           let timeComponents = parseTime(timeValue) {
            draft.time = .init(hour: timeComponents.hour ?? 0, minute: timeComponents.minute ?? 0)
            if let date = Calendar.current.date(from: timeComponents) {
                time = date
            }
        }
    }

    private func parseSuggestion(from text: String) -> AIScheduleFormSuggestion? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else { return nil }
        let jsonText = String(text[start...end])
        guard let data = jsonText.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(AIScheduleFormSuggestion.self, from: data) else { return nil }
        return decoded
    }

    private func parseTime(_ value: String) -> DateComponents? {
        let parts = value.split(separator: ":").map { String($0) }
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else { return nil }
        return DateComponents(hour: hour, minute: minute)
    }

    private func buildPrompt(userGoal: String) -> String {
        let isChinese = LanguageManager.shared.selectedLanguage == "zh-Hans"
        if isChinese {
            return """
            你正在为 SwiftCraftServerLauncher 创建定时任务。请严格输出 JSON，不要输出其他文字。
            JSON 字段：
            name, action, trigger, keyword, command, time, weekdays, useRegex, ignoreCase

            规则：
            - action: start|stop|restart|command
            - trigger: time|consoleKeyword
            - time: 24 小时制 HH:mm
            - weekdays: 1-7 的数组（周日=1，周一=2...周六=7）
            - keyword/command 只在需要时填写
            - 命令模板支持：{{line}}, {{0}}, {{1}}..., {{re:pattern|1}}, {{/pattern/|1}}
            - 如需原始整行，使用 {{raw}}
            - 仅输出 JSON 对象，不要解释

            示例：
            {"name":"自动重启","action":"restart","trigger":"time","time":"03:00","weekdays":[2,4,6]}
            {"name":"检测关键字","action":"command","trigger":"consoleKeyword","keyword":"error","command":"say {{line}}","useRegex":false,"ignoreCase":true}

            服务器：\(serverName)
            用户需求：\(userGoal.isEmpty ? "创建一个定时任务。" : userGoal)
            """
        }
        return """
        You are creating a schedule in SwiftCraftServerLauncher. Output STRICT JSON only.
        JSON fields:
        name, action, trigger, keyword, command, time, weekdays, useRegex, ignoreCase

        Rules:
        - action: start|stop|restart|command
        - trigger: time|consoleKeyword
        - time: HH:mm (24h)
        - weekdays: array of 1-7 (Sun=1 ... Sat=7)
        - keyword/command only when needed
        - command template supports: {{line}}, {{0}}, {{1}}..., {{re:pattern|1}}, {{/pattern/|1}}
        - use {{raw}} for the original full line
        - return JSON only, no extra text

        Examples:
        {"name":"Auto restart","action":"restart","trigger":"time","time":"03:00","weekdays":[2,4,6]}
        {"name":"Keyword trigger","action":"command","trigger":"consoleKeyword","keyword":"error","command":"say {{line}}","useRegex":false,"ignoreCase":true}

        Server: \(serverName)
        User request: \(userGoal.isEmpty ? "Create a schedule." : userGoal)
        """
    }
}

private struct AIScheduleFormSuggestion: Codable {
    let name: String?
    let action: String?
    let trigger: String?
    let keyword: String?
    let command: String?
    let time: String?
    let weekdays: [Int]?
    let useRegex: Bool
    let ignoreCase: Bool

    init(
        name: String? = nil,
        action: String? = nil,
        trigger: String? = nil,
        keyword: String? = nil,
        command: String? = nil,
        time: String? = nil,
        weekdays: [Int]? = nil,
        useRegex: Bool = false,
        ignoreCase: Bool = true
    ) {
        self.name = name
        self.action = action
        self.trigger = trigger
        self.keyword = keyword
        self.command = command
        self.time = time
        self.weekdays = weekdays
        self.useRegex = useRegex
        self.ignoreCase = ignoreCase
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        action = try container.decodeIfPresent(String.self, forKey: .action)
        trigger = try container.decodeIfPresent(String.self, forKey: .trigger)
        keyword = try container.decodeIfPresent(String.self, forKey: .keyword)
        command = try container.decodeIfPresent(String.self, forKey: .command)
        time = try container.decodeIfPresent(String.self, forKey: .time)
        weekdays = try container.decodeIfPresent([Int].self, forKey: .weekdays)
        useRegex = try container.decodeIfPresent(Bool.self, forKey: .useRegex) ?? false
        ignoreCase = try container.decodeIfPresent(Bool.self, forKey: .ignoreCase) ?? true
    }
}

private extension ServerSchedule.Action {
    static func fromString(_ value: String) -> ServerSchedule.Action? {
        switch value.lowercased() {
        case "start": return .start
        case "stop": return .stop
        case "restart": return .restart
        case "command": return .command
        default: return nil
        }
    }
}

private extension ServerSchedule.Trigger {
    static func fromString(_ value: String) -> ServerSchedule.Trigger? {
        let normalized = value.lowercased()
        if normalized == "time" { return .time }
        if normalized == "consolekeyword" || normalized == "consolekey" || normalized == "console" {
            return .consoleKeyword
        }
        return nil
    }
}
