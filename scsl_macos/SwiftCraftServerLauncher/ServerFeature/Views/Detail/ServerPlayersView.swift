import SwiftUI

struct ServerPlayersView: View {
    let server: ServerInstance
    @EnvironmentObject var serverNodeRepository: ServerNodeRepository
    @StateObject private var serverStatusManager = ServerStatusManager.shared
    @State private var whitelist: [ServerPlayerListService.PlayerEntry] = []
    @State private var ops: [ServerPlayerListService.PlayerEntry] = []
    @State private var bannedPlayers: [ServerPlayerListService.PlayerEntry] = []
    @State private var bannedIps: [ServerPlayerListService.PlayerEntry] = []

    @State private var newName: String = ""
    @State private var selectedList: String = "whitelist"
    @State private var expandedSections: Set<String> = []
    private let collapsedPreviewCount = 4
    private let autoRefreshTimer = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    var body: some View {
        ServerDetailPage(
            title: "server.players.title".localized()
        ) {
            VStack(alignment: .leading, spacing: 8) {
                    if serverStatusManager.isServerRunning(serverId: server.id) {
                        Text("server.players.running_hint".localized())
                            .foregroundColor(.secondary)
                    } else {
                        Text("server.players.stopped_hint".localized())
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.badge.plus")
                                .foregroundStyle(.secondary)
                            Text("server.players.quick_add.title".localized())
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                        }

                        HStack(spacing: 8) {
                            TextField(
                                selectedList == "bannedIps"
                                    ? "server.players.placeholder.banned_ips".localized()
                                    : "server.players.name_placeholder".localized(),
                                text: $newName
                            )
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addEntry() }

                            Menu {
                                Button("server.players.list.whitelist".localized()) { selectedList = "whitelist" }
                                Button("server.players.list.ops".localized()) { selectedList = "ops" }
                                Button("server.players.list.banned_players".localized()) { selectedList = "bannedPlayers" }
                                Button("server.players.list.banned_ips".localized()) { selectedList = "bannedIps" }
                            } label: {
                                Label(selectedListTitle, systemImage: selectedListIcon)
                                    .frame(minWidth: 150, alignment: .leading)
                            }

                            Button {
                                addEntry()
                            } label: {
                                Label("common.add".localized(), systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.gray.opacity(0.08))
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if selectedList == "bannedIps" {
                        Text("server.players.banned_ip_hint".localized())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            playerList(sectionKey: "whitelist", title: "server.players.list.whitelist".localized(), entries: whitelist) { removeEntry(from: "whitelist", entry: $0) }
                            playerList(sectionKey: "ops", title: "server.players.list.ops".localized(), entries: ops) { removeEntry(from: "ops", entry: $0) }
                            playerList(sectionKey: "bannedPlayers", title: "server.players.list.banned_players".localized(), entries: bannedPlayers) { removeEntry(from: "bannedPlayers", entry: $0) }
                            playerList(sectionKey: "bannedIps", title: "server.players.list.banned_ips".localized(), entries: bannedIps) { removeEntry(from: "bannedIps", entry: $0) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onAppear { loadAll() }
        .onReceive(autoRefreshTimer) { _ in
            loadAll()
        }
    }

    private func playerList(
        sectionKey: String,
        title: String,
        entries: [ServerPlayerListService.PlayerEntry],
        onRemove: @escaping (ServerPlayerListService.PlayerEntry) -> Void
    ) -> some View {
        let isExpanded = expandedSections.contains(sectionKey)
        let shouldCollapse = entries.count > collapsedPreviewCount
        let shownEntries = shouldCollapse && !isExpanded ? Array(entries.prefix(collapsedPreviewCount)) : entries

        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            if entries.isEmpty {
                Text("common.empty".localized())
                    .foregroundColor(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(shownEntries, id: \.self) { entry in
                    HStack {
                        Text(entry.name)
                        Spacer()
                        Button("common.remove".localized()) { onRemove(entry) }
                    }
                    if entry != shownEntries.last {
                        Divider()
                    }
                }
                if shouldCollapse {
                    Divider()
                    Button {
                        toggleExpand(sectionKey: sectionKey)
                    } label: {
                        HStack(spacing: 6) {
                            Text(
                                isExpanded
                                    ? "server.players.collapse".localized()
                                    : String(format: "server.players.more_count".localized(), entries.count - collapsedPreviewCount)
                            )
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.08))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleExpand(sectionKey: String) {
        if expandedSections.contains(sectionKey) {
            expandedSections.remove(sectionKey)
        } else {
            expandedSections.insert(sectionKey)
        }
    }

    private var selectedListTitle: String {
        switch selectedList {
        case "whitelist":
            return "server.players.list.whitelist".localized()
        case "ops":
            return "server.players.list.ops".localized()
        case "bannedPlayers":
            return "server.players.list.banned_players".localized()
        case "bannedIps":
            return "server.players.list.banned_ips".localized()
        default:
            return "server.players.list.whitelist".localized()
        }
    }

    private var selectedListIcon: String {
        switch selectedList {
        case "whitelist":
            return "checkmark.shield"
        case "ops":
            return "person.crop.circle.badge.checkmark"
        case "bannedPlayers":
            return "person.crop.circle.badge.xmark"
        case "bannedIps":
            return "network.slash"
        default:
            return "checkmark.shield"
        }
    }

    private func loadAll() {
        if isRemoteServer {
            loadRemoteLists()
            return
        }
        let dir = AppPaths.serverDirectory(serverName: server.directoryName)
        do {
            whitelist = try ServerPlayerListService.readList(serverDir: dir, fileName: "whitelist.json")
            ops = try ServerPlayerListService.readList(serverDir: dir, fileName: "ops.json")
            bannedPlayers = try ServerPlayerListService.readList(serverDir: dir, fileName: "banned-players.json")
            bannedIps = try ServerPlayerListService.readList(serverDir: dir, fileName: "banned-ips.json")
        } catch {
            GlobalErrorHandler.shared.handle(error)
        }
    }

    private func saveAll() {
        if isRemoteServer {
            saveRemoteLists()
            return
        }
        if serverStatusManager.isServerRunning(serverId: server.id) { return }
        let dir = AppPaths.serverDirectory(serverName: server.directoryName)
        do {
            try ServerPlayerListService.writeList(serverDir: dir, fileName: "whitelist.json", entries: whitelist)
            try ServerPlayerListService.writeList(serverDir: dir, fileName: "ops.json", entries: ops)
            try ServerPlayerListService.writeList(serverDir: dir, fileName: "banned-players.json", entries: bannedPlayers)
            try ServerPlayerListService.writeList(serverDir: dir, fileName: "banned-ips.json", entries: bannedIps)
        } catch {
            GlobalErrorHandler.shared.handle(error)
        }
    }

    private func addEntry() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
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
        newName = ""
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
