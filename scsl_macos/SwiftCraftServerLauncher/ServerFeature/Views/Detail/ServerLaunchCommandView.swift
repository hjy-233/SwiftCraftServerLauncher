import SwiftUI

struct ServerLaunchCommandView: View {
    let server: ServerInstance
    @EnvironmentObject var detailState: ResourceDetailState
    @StateObject private var generalSettings = GeneralSettingsManager.shared
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
        NavigationStack {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(sectionItems) { item in
                    Button {
                        guard item.isEnabled else { return }
                        detailState.serverPanelSection = item.section.rawValue
                    } label: {
                        Label(item.title, systemImage: item.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.large)
                    .foregroundStyle(item.isEnabled ? .primary : .tertiary)
                    .disabled(!item.isEnabled)
                }

                ForEach(sectionItems.filter { !$0.isEnabled && $0.disabledHint != nil }) { item in
                    if let disabledHint = item.disabledHint {
                        Text(disabledHint)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 26)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color.clear)
        .frame(minWidth: 170, idealWidth: 180, maxWidth: 220, maxHeight: .infinity, alignment: .top)
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

    private var sectionItems: [ServerDetailSectionItem] {
        ServerDetailSectionProvider.items(for: server, settings: generalSettings)
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
