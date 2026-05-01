import SwiftUI

private enum ServerDetailSection: String, CaseIterable, Identifiable {
    case console
    case serverConfig
    case players
    case worlds
    case mods
    case plugins
    case schedules
    case logs

    var id: String { rawValue }
}

struct ServerLaunchCommandView: View {
    let server: ServerInstance
    @EnvironmentObject var detailState: ResourceDetailState
    @StateObject private var generalSettings = GeneralSettingsManager.shared
    @Namespace private var sectionIndicatorNamespace
    private var supportsMods: Bool {
        server.serverType == .fabric || server.serverType == .forge
    }
    private var supportsPlugins: Bool {
        server.serverType == .paper
    }
    private var tabSettingsToken: String {
        [
            generalSettings.serverTabConsoleEnabled,
            generalSettings.serverTabConfigEnabled,
            generalSettings.serverTabPlayersEnabled,
            generalSettings.serverTabWorldsEnabled,
            generalSettings.serverTabModsEnabled,
            generalSettings.serverTabPluginsEnabled,
            generalSettings.serverTabSchedulesEnabled,
            generalSettings.serverTabLogsEnabled,
        ]
        .map { $0 ? "1" : "0" }
        .joined()
    }
    private var currentSection: ServerDetailSection {
        let requested = ServerDetailSection(rawValue: detailState.serverPanelSection) ?? .console
        switch requested {
        case .mods where !supportsMods:
            return .console
        case .plugins where !supportsPlugins:
            return .console
        default:
            return requested
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sectionItems) { item in
                        sectionRow(
                            section: item.section,
                            title: item.title,
                            icon: item.icon,
                            isEnabled: item.isEnabled,
                            disabledHint: item.disabledHint
                        )
                    }
                }
                .frame(width: 180, alignment: .topLeading)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            normalizeSelectedSectionIfNeeded()
        }
        .onChange(of: server.id) { _, _ in
            normalizeSelectedSectionIfNeeded()
        }
        .onChange(of: detailState.serverPanelSection) { _, _ in
            normalizeSelectedSectionIfNeeded()
        }
        .onChange(of: tabSettingsToken) { _, _ in
            normalizeSelectedSectionIfNeeded()
        }
        .onChange(of: server.serverType) { _, _ in
            normalizeSelectedSectionIfNeeded()
        }
    }

    private struct SectionItem: Identifiable {
        let section: ServerDetailSection
        let title: String
        let icon: String
        let isEnabled: Bool
        let disabledHint: String?

        var id: String { section.rawValue }
    }

    private var sectionItems: [SectionItem] {
        var items: [SectionItem] = []
        if generalSettings.serverTabConsoleEnabled {
            items.append(.init(
                section: .console,
                title: "server.console.title".localized(),
                icon: "terminal",
                isEnabled: true,
                disabledHint: nil
            ))
        }
        if generalSettings.serverTabConfigEnabled {
            items.append(.init(
                section: .serverConfig,
                title: "server.launch.server_config".localized(),
                icon: "folder",
                isEnabled: true,
                disabledHint: nil
            ))
        }
        if generalSettings.serverTabPlayersEnabled {
            items.append(.init(
                section: .players,
                title: "server.launch.players".localized(),
                icon: "person.3",
                isEnabled: true,
                disabledHint: nil
            ))
        }
        if generalSettings.serverTabWorldsEnabled {
            items.append(.init(
                section: .worlds,
                title: "server.launch.worlds".localized(),
                icon: "globe.americas",
                isEnabled: true,
                disabledHint: nil
            ))
        }
        if generalSettings.serverTabModsEnabled {
            items.append(.init(
                section: .mods,
                title: "server.launch.mods".localized(),
                icon: "puzzlepiece.extension",
                isEnabled: supportsMods,
                disabledHint: "server.launch.hint.mods_only".localized()
            ))
        }
        if generalSettings.serverTabPluginsEnabled {
            items.append(.init(
                section: .plugins,
                title: "server.launch.plugins".localized(),
                icon: "powerplug",
                isEnabled: supportsPlugins,
                disabledHint: "server.launch.hint.plugins_only".localized()
            ))
        }
        if generalSettings.serverTabSchedulesEnabled {
            items.append(.init(
                section: .schedules,
                title: "server.schedules.title".localized(),
                icon: "clock.arrow.circlepath",
                isEnabled: true,
                disabledHint: nil
            ))
        }
        if generalSettings.serverTabLogsEnabled {
            items.append(.init(
                section: .logs,
                title: "server.logs.title".localized(),
                icon: "doc.text.magnifyingglass",
                isEnabled: true,
                disabledHint: nil,
            ))
        }
        if items.isEmpty {
            items.append(.init(
                section: .console,
                title: "server.console.title".localized(),
                icon: "terminal",
                isEnabled: true,
                disabledHint: nil
            ))
        }
        return items
    }

    private func sectionRow(
        section: ServerDetailSection,
        title: String,
        icon: String,
        isEnabled: Bool = true,
        disabledHint: String? = nil
    ) -> some View {
        let rowButton = Button {
            guard isEnabled else { return }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                detailState.serverPanelSection = section.rawValue
            }
        } label: {
            HStack(spacing: 8) {
                if currentSection == section {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: 3, height: 16)
                        .matchedGeometryEffect(id: "server-section-indicator", in: sectionIndicatorNamespace)
                } else {
                    Color.clear
                        .frame(width: 3, height: 16)
                }
                Image(systemName: icon)
                    .frame(width: 16)
                Text(title)
                    .lineLimit(1)
                if !isEnabled, let disabledHint {
                    Text(disabledHint)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .foregroundStyle(isEnabled ? (currentSection == section ? Color.primary : Color.secondary) : Color.secondary.opacity(0.6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isEnabled ? 1 : 0.65)
        .disabled(!isEnabled)

        return rowButton
    }

    private func normalizeSelectedSectionIfNeeded() {
        let allowed = sectionItems.filter { $0.isEnabled }.map(\.section)
        let fallback = allowed.first ?? .console
        if !allowed.contains(currentSection) {
            detailState.serverPanelSection = fallback.rawValue
            return
        }
        if currentSection == .mods, !supportsMods {
            detailState.serverPanelSection = fallback.rawValue
            return
        }
        if currentSection == .plugins, !supportsPlugins {
            detailState.serverPanelSection = fallback.rawValue
        }
    }
}
