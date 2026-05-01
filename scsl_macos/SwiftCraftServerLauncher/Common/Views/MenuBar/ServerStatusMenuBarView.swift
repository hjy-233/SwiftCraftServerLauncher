import SwiftUI

struct ServerStatusMenuBarView: View {
    @EnvironmentObject private var serverRepository: ServerRepository
    @ObservedObject private var statusManager = ServerStatusManager.shared
    @ObservedObject private var generalSettings = GeneralSettingsManager.shared

    private var runningServersCount: Int {
        serverRepository.servers.filter { statusManager.isServerRunning(serverId: $0.id) }.count
    }

    var body: some View {
        Group {
            if serverRepository.servers.isEmpty {
                ContentUnavailableView(
                    "menubar.servers.empty".localized(),
                    systemImage: "server.rack"
                )
            } else {
                serverList
            }
        }
    }

    private var serverList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(format: "menubar.servers.summary".localized(), runningServersCount, serverRepository.servers.count))
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            ForEach(serverRepository.servers) { server in
                Menu {
                    ForEach(sectionItems(for: server)) { item in
                        Button {
                            guard item.isEnabled else { return }
                            ServerDetailWindowCoordinator.shared.open(
                                serverId: server.id,
                                preferredSection: item.section
                            )
                        } label: {
                            Label(item.title, systemImage: item.icon)
                        }
                        .disabled(!item.isEnabled)
                    }
                } label: {
                    HStack {
                        Image(systemName: statusIconName(for: server))
                            .foregroundStyle(statusColor(for: server))
                        Text(server.name)
                        Spacer()
                        Text(statusText(for: server))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private struct SectionItem: Identifiable {
        let section: String
        let title: String
        let icon: String
        let isEnabled: Bool

        var id: String { section }
    }

    private func sectionItems(for server: ServerInstance) -> [SectionItem] {
        var items: [SectionItem] = []
        if generalSettings.serverTabConsoleEnabled {
            items.append(.init(
                section: "console",
                title: "server.console.title".localized(),
                icon: "terminal",
                isEnabled: true
            ))
        }
        if generalSettings.serverTabConfigEnabled {
            items.append(.init(
                section: "serverConfig",
                title: "server.launch.server_config".localized(),
                icon: "folder",
                isEnabled: true
            ))
        }
        if generalSettings.serverTabPlayersEnabled {
            items.append(.init(
                section: "players",
                title: "server.launch.players".localized(),
                icon: "person.3",
                isEnabled: true
            ))
        }
        if generalSettings.serverTabWorldsEnabled {
            items.append(.init(
                section: "worlds",
                title: "server.launch.worlds".localized(),
                icon: "globe.americas",
                isEnabled: true
            ))
        }
        if generalSettings.serverTabModsEnabled {
            items.append(.init(
                section: "mods",
                title: disabledTitle(
                    "server.launch.mods".localized(),
                    hint: supportsMods(server) ? nil : "server.launch.hint.mods_only".localized()
                ),
                icon: "puzzlepiece.extension",
                isEnabled: supportsMods(server)
            ))
        }
        if generalSettings.serverTabPluginsEnabled {
            items.append(.init(
                section: "plugins",
                title: disabledTitle(
                    "server.launch.plugins".localized(),
                    hint: supportsPlugins(server) ? nil : "server.launch.hint.plugins_only".localized()
                ),
                icon: "powerplug",
                isEnabled: supportsPlugins(server)
            ))
        }
        if generalSettings.serverTabSchedulesEnabled {
            items.append(.init(
                section: "schedules",
                title: "server.schedules.title".localized(),
                icon: "clock.arrow.circlepath",
                isEnabled: true
            ))
        }
        if generalSettings.serverTabLogsEnabled {
            items.append(.init(
                section: "logs",
                title: "server.logs.title".localized(),
                icon: "doc.text.magnifyingglass",
                isEnabled: true
            ))
        }
        if items.isEmpty {
            items.append(.init(
                section: "console",
                title: "server.console.title".localized(),
                icon: "terminal",
                isEnabled: true
            ))
        }
        return items
    }

    private func supportsMods(_ server: ServerInstance) -> Bool {
        server.serverType == .fabric || server.serverType == .forge
    }

    private func supportsPlugins(_ server: ServerInstance) -> Bool {
        server.serverType == .paper
    }

    private func disabledTitle(_ title: String, hint: String?) -> String {
        guard let hint else { return title }
        return "\(title)  \(hint)"
    }

    private func statusText(for server: ServerInstance) -> String {
        if statusManager.isServerLaunching(serverId: server.id) {
            return "menubar.servers.status.launching".localized()
        }
        if statusManager.isServerRunning(serverId: server.id) {
            return "menubar.servers.status.running".localized()
        }
        return "menubar.servers.status.stopped".localized()
    }

    private func statusIconName(for server: ServerInstance) -> String {
        if statusManager.isServerLaunching(serverId: server.id) {
            return "clock.fill"
        }
        if statusManager.isServerRunning(serverId: server.id) {
            return "circle.fill"
        }
        return "circle"
    }

    private func statusColor(for server: ServerInstance) -> Color {
        if statusManager.isServerLaunching(serverId: server.id) {
            return .orange
        }
        if statusManager.isServerRunning(serverId: server.id) {
            return .green
        }
        return .secondary
    }
}
