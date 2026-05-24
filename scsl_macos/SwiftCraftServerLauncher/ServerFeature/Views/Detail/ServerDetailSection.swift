import Foundation

enum ServerDetailSection: String, CaseIterable, Identifiable {
    case console
    case serverConfig
    case players
    case worlds
    case mods
    case plugins
    case schedules
    case logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .console:
            "server.console.title".localized()
        case .serverConfig:
            "server.launch.server_config".localized()
        case .players:
            "server.launch.players".localized()
        case .worlds:
            "server.launch.worlds".localized()
        case .mods:
            "server.launch.mods".localized()
        case .plugins:
            "server.launch.plugins".localized()
        case .schedules:
            "server.schedules.title".localized()
        case .logs:
            "server.logs.title".localized()
        }
    }

    var systemImage: String {
        switch self {
        case .console:
            "terminal"
        case .serverConfig:
            "folder"
        case .players:
            "person.3"
        case .worlds:
            "globe.americas"
        case .mods:
            "puzzlepiece.extension"
        case .plugins:
            "powerplug"
        case .schedules:
            "clock.arrow.circlepath"
        case .logs:
            "doc.text.magnifyingglass"
        }
    }
}

struct ServerDetailSectionItem: Identifiable {
    let section: ServerDetailSection
    let isEnabled: Bool
    let disabledHint: String?

    var id: String { section.rawValue }
    var title: String { section.title }
    var icon: String { section.systemImage }
}

enum ServerDetailSectionProvider {
    static func items(
        for server: ServerInstance,
        settings: GeneralSettingsManager
    ) -> [ServerDetailSectionItem] {
        var items: [ServerDetailSectionItem] = []
        let supportsMods = server.serverType == .fabric || server.serverType == .forge
        let supportsPlugins = server.serverType == .paper

        if settings.serverTabConsoleEnabled {
            items.append(.init(section: .console, isEnabled: true, disabledHint: nil))
        }
        if settings.serverTabConfigEnabled {
            items.append(.init(section: .serverConfig, isEnabled: true, disabledHint: nil))
        }
        if settings.serverTabPlayersEnabled {
            items.append(.init(section: .players, isEnabled: true, disabledHint: nil))
        }
        if settings.serverTabWorldsEnabled {
            items.append(.init(section: .worlds, isEnabled: true, disabledHint: nil))
        }
        if settings.serverTabModsEnabled {
            items.append(.init(
                section: .mods,
                isEnabled: supportsMods,
                disabledHint: "server.launch.hint.mods_only".localized()
            ))
        }
        if settings.serverTabPluginsEnabled {
            items.append(.init(
                section: .plugins,
                isEnabled: supportsPlugins,
                disabledHint: "server.launch.hint.plugins_only".localized()
            ))
        }
        if settings.serverTabSchedulesEnabled {
            items.append(.init(section: .schedules, isEnabled: true, disabledHint: nil))
        }
        if settings.serverTabLogsEnabled {
            items.append(.init(section: .logs, isEnabled: true, disabledHint: nil))
        }

        if items.isEmpty {
            items.append(.init(section: .console, isEnabled: true, disabledHint: nil))
        }
        return items
    }
}
