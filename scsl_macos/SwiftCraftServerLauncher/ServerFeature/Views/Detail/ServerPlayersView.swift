import SwiftUI

struct ServerPlayersView: View {
    let server: ServerInstance
    @EnvironmentObject var serverNodeRepository: ServerNodeRepository
    @StateObject private var serverStatusManager = ServerStatusManager.shared
    @State private var whitelist: [ServerPlayerListService.PlayerEntry] = []
    @State private var ops: [ServerPlayerListService.PlayerEntry] = []
    @State private var bannedPlayers: [ServerPlayerListService.PlayerEntry] = []
    @State private var bannedIps: [ServerPlayerListService.PlayerEntry] = []

    @State private var newNames: String = ""
    @State private var selectedList: String?
    @State private var selectedPlayerId: String?
    @State private var showsAddSheet = false
    @State private var isSavingPlayerLists = false
    @StateObject private var toolbarSelection = ServerDetailToolbarSelectionState.shared
    private let autoRefreshTimer = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    var body: some View {
        ServerDetailPage(
            title: "server.players.title".localized()
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Group {
                    if serverStatusManager.isServerRunning(serverId: server.id) {
                        Text("server.players.running_hint".localized())
                            .foregroundColor(.secondary)
                    } else {
                        Text("server.players.stopped_hint".localized())
                            .foregroundColor(.secondary)
                    }
                }
                .font(.callout)

                groupSelector
                playerEntriesList
            }
        }
        .onAppear {
            if selectedList == nil {
                selectedList = "whitelist"
            }
            loadAll()
        }
        .onReceive(autoRefreshTimer) { _ in
            loadAll()
        }
        .onChange(of: selectedList) { _, newValue in
            toolbarSelection.selectedPlayerGroupByServerId[server.id] = newValue
            selectedPlayerId = nil
            toolbarSelection.selectedPlayerIdByServerId[server.id] = nil
        }
        .onChange(of: selectedPlayerId) { _, newValue in
            toolbarSelection.selectedPlayerIdByServerId[server.id] = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverDetailToolbarAction)) { notification in
            guard let action = ServerDetailToolbarActionBus.action(from: notification) else { return }
            if action == .playersRemove {
                removeSelectedEntry()
                return
            }
            guard action == .playersAdd else { return }
            newNames = ""
            showsAddSheet = selectedList != nil
        }
        .sheet(isPresented: $showsAddSheet) {
            playerAddSheet
        }
        .onDisappear {
            toolbarSelection.selectedPlayerGroupByServerId[server.id] = nil
            toolbarSelection.selectedPlayerIdByServerId[server.id] = nil
        }
    }

    private var groupSelector: some View {
        Picker("", selection: selectedListBinding) {
            Text("server.players.list.whitelist".localized()).tag("whitelist")
            Text("server.players.list.ops".localized()).tag("ops")
            Text("server.players.list.banned_players".localized()).tag("bannedPlayers")
            Text("server.players.list.banned_ips".localized()).tag("bannedIps")
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }

    private var playerEntriesList: some View {
        List(selection: $selectedPlayerId) {
            if selectedList == nil {
                Text("common.empty".localized())
                    .foregroundColor(.secondary)
            } else {
                ForEach(currentEntries, id: \.self) { entry in
                    Text(entry.name)
                        .padding(.vertical, 2)
                        .tag(playerEntryId(entry))
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectedListBinding: Binding<String> {
        Binding(
            get: { selectedList ?? "whitelist" },
            set: { selectedList = $0 }
        )
    }

    private var currentEntries: [ServerPlayerListService.PlayerEntry] {
        switch selectedList {
        case "whitelist":
            whitelist
        case "ops":
            ops
        case "bannedPlayers":
            bannedPlayers
        case "bannedIps":
            bannedIps
        default:
            []
        }
    }

    private func playerEntryId(_ entry: ServerPlayerListService.PlayerEntry) -> String {
        [selectedList ?? "", entry.uuid, entry.name, entry.ip ?? ""].joined(separator: "|")
    }

    private func loadAll() {
        guard !isSavingPlayerLists else { return }
        if isRemoteServer {
            loadRemoteLists()
            return
        }
        Task {
            do {
                async let loadedWhitelist = ServerPlayerListService.readList(server: server, fileName: "whitelist.json")
                async let loadedOps = ServerPlayerListService.readList(server: server, fileName: "ops.json")
                async let loadedBannedPlayers = ServerPlayerListService.readList(server: server, fileName: "banned-players.json")
                async let loadedBannedIps = ServerPlayerListService.readList(server: server, fileName: "banned-ips.json")

                let values = try await (
                    loadedWhitelist,
                    loadedOps,
                    loadedBannedPlayers,
                    loadedBannedIps
                )
                await MainActor.run {
                    whitelist = values.0
                    ops = values.1
                    bannedPlayers = values.2
                    bannedIps = values.3
                }
            } catch {
                GlobalErrorHandler.shared.handle(error)
            }
        }
    }

    private func saveAll() {
        if isRemoteServer {
            saveRemoteLists()
            return
        }
        if serverStatusManager.isServerRunning(serverId: server.id) { return }
        isSavingPlayerLists = true
        let currentWhitelist = whitelist
        let currentOps = ops
        let currentBannedPlayers = bannedPlayers
        let currentBannedIps = bannedIps
        Task {
            do {
                try await ServerPlayerListService.writeList(server: server, fileName: "whitelist.json", entries: currentWhitelist)
                try await ServerPlayerListService.writeList(server: server, fileName: "ops.json", entries: currentOps)
                try await ServerPlayerListService.writeList(server: server, fileName: "banned-players.json", entries: currentBannedPlayers)
                try await ServerPlayerListService.writeList(server: server, fileName: "banned-ips.json", entries: currentBannedIps)
            } catch {
                GlobalErrorHandler.shared.handle(error)
            }
            await MainActor.run {
                isSavingPlayerLists = false
            }
        }
    }

    private var playerAddSheet: some View {
        CommonSheetView {
            Text("server.players.add.title".localized())
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
        } body: {
            VStack(alignment: .leading, spacing: 10) {
                TextField(
                    selectedList == "bannedIps"
                        ? "server.players.placeholder.banned_ips".localized()
                        : "server.players.name_placeholder".localized(),
                    text: $newNames
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit { addEntries() }

                Text("server.players.add.batch_hint".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 420)
        } footer: {
            HStack {
                Spacer()
                Button("common.cancel".localized()) {
                    showsAddSheet = false
                }
                Button("common.add".localized()) {
                    addEntries()
                }
                .buttonStyle(.borderedProminent)
                .disabled(playerNamesToAdd.isEmpty)
            }
        }
    }

    private var playerNamesToAdd: [String] {
        newNames
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func addEntries() {
        let names = playerNamesToAdd
        guard !names.isEmpty else { return }
        names.forEach(addEntry)
        newNames = ""
        showsAddSheet = false
    }

    private func addEntry(name: String) {
        guard !name.isEmpty else { return }
        guard let selectedList else { return }
        let entry = ServerPlayerListService.PlayerEntry(uuid: "", name: name, level: nil, bypassesPlayerLimit: false, created: nil, source: nil, expires: nil, reason: nil, ip: nil)
        let isRunning = serverStatusManager.isServerRunning(serverId: server.id)

        switch selectedList {
        case "whitelist":
            whitelist.append(entry)
            if isRunning { sendCommand("whitelist add \(name)") }
        case "ops":
            ops.append(entry)
            if isRunning { sendCommand("op \(name)") }
        case "bannedPlayers":
            bannedPlayers.append(entry)
            if isRunning { sendCommand("ban \(name)") }
        case "bannedIps":
            var ipEntry = entry
            ipEntry.ip = name
            ipEntry.name = name
            bannedIps.append(ipEntry)
            if isRunning { sendCommand("ban-ip \(name)") }
        default:
            break
        }
        if !isRunning { saveAll() }
    }

    private func removeEntry(from list: String, entry: ServerPlayerListService.PlayerEntry) {
        let isRunning = serverStatusManager.isServerRunning(serverId: server.id)
        switch list {
        case "whitelist":
            whitelist.removeAll { $0 == entry }
            if isRunning { sendCommand("whitelist remove \(entry.name)") }
        case "ops":
            ops.removeAll { $0 == entry }
            if isRunning { sendCommand("deop \(entry.name)") }
        case "bannedPlayers":
            bannedPlayers.removeAll { $0 == entry }
            if isRunning { sendCommand("pardon \(entry.name)") }
        case "bannedIps":
            bannedIps.removeAll { $0 == entry }
            if isRunning { sendCommand("pardon-ip \(entry.name)") }
        default:
            break
        }
        if !isRunning { saveAll() }
    }

    private func removeSelectedEntry() {
        guard let selectedList, let selectedPlayerId else { return }
        guard let entry = currentEntries.first(where: { playerEntryId($0) == selectedPlayerId }) else { return }
        removeEntry(from: selectedList, entry: entry)
        self.selectedPlayerId = nil
    }

    private var isRemoteServer: Bool {
        server.nodeId != ServerNode.local.id || server.javaPath == "java"
    }

    private func sendCommand(_ command: String) {
        if !isRemoteServer {
            ServerConsoleManager.shared.send(serverId: server.id, command: command)
            return
        }
        guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
        Task {
            do {
                if server.consoleMode == .rcon {
                    _ = try await RCONService.execute(
                        host: node.host,
                        port: UInt16(server.rconPort),
                        password: server.rconPassword,
                        command: command
                    )
                } else {
                    do {
                        try await SSHNodeService.sendRemoteDirectCommand(node: node, serverName: server.name, command: command)
                    } catch {
                        _ = try await RCONService.execute(
                            host: node.host,
                            port: UInt16(server.rconPort),
                            password: server.rconPassword,
                            command: command
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

    private func loadRemoteLists() {
        guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
        Task {
            do {
                async let whitelistText = SSHNodeService.readRemoteConfigFile(node: node, serverName: server.name, relativePath: "whitelist.json")
                async let opsText = SSHNodeService.readRemoteConfigFile(node: node, serverName: server.name, relativePath: "ops.json")
                async let bannedPlayersText = SSHNodeService.readRemoteConfigFile(node: node, serverName: server.name, relativePath: "banned-players.json")
                async let bannedIpsText = SSHNodeService.readRemoteConfigFile(node: node, serverName: server.name, relativePath: "banned-ips.json")

                let loadedWhitelist = decodeRemotePlayerList(try await whitelistText)
                let loadedOps = decodeRemotePlayerList(try await opsText)
                let loadedBannedPlayers = decodeRemotePlayerList(try await bannedPlayersText)
                let loadedBannedIps = decodeRemotePlayerList(try await bannedIpsText)

                await MainActor.run {
                    whitelist = loadedWhitelist
                    ops = loadedOps
                    bannedPlayers = loadedBannedPlayers
                    bannedIps = loadedBannedIps
                }
            } catch {
                await MainActor.run {
                    whitelist = []
                    ops = []
                    bannedPlayers = []
                    bannedIps = []
                }
            }
        }
    }

    private func saveRemoteLists() {
        guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
        if serverStatusManager.isServerRunning(serverId: server.id) { return }
        isSavingPlayerLists = true
        Task {
            do {
                try await SSHNodeService.writeRemoteConfigFile(
                    node: node,
                    serverName: server.name,
                    relativePath: "whitelist.json",
                    content: encodeRemotePlayerList(whitelist)
                )
                try await SSHNodeService.writeRemoteConfigFile(
                    node: node,
                    serverName: server.name,
                    relativePath: "ops.json",
                    content: encodeRemotePlayerList(ops)
                )
                try await SSHNodeService.writeRemoteConfigFile(
                    node: node,
                    serverName: server.name,
                    relativePath: "banned-players.json",
                    content: encodeRemotePlayerList(bannedPlayers)
                )
                try await SSHNodeService.writeRemoteConfigFile(
                    node: node,
                    serverName: server.name,
                    relativePath: "banned-ips.json",
                    content: encodeRemotePlayerList(bannedIps)
                )
            } catch {
                await MainActor.run { GlobalErrorHandler.shared.handle(error) }
            }
            await MainActor.run {
                isSavingPlayerLists = false
            }
        }
    }

    private func decodeRemotePlayerList(_ text: String) -> [ServerPlayerListService.PlayerEntry] {
        guard let data = text.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ServerPlayerListService.PlayerEntry].self, from: data)) ?? []
    }

    private func encodeRemotePlayerList(_ entries: [ServerPlayerListService.PlayerEntry]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return "[]\n" }
        return (String(bytes: data, encoding: .utf8) ?? "[]") + "\n"
    }
}
