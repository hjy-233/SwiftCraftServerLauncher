import AppKit
import SwiftUI

struct ServerDetailWindowView: View {
    @StateObject private var coordinator = ServerDetailWindowCoordinator.shared
    let serverId: String
    @State private var hostWindow: NSWindow?
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @StateObject private var filterState = ResourceFilterState()
    @StateObject private var detailState = ResourceDetailState()
    @EnvironmentObject private var serverRepository: ServerRepository
    @EnvironmentObject private var serverNodeRepository: ServerNodeRepository
    @EnvironmentObject private var serverLaunchUseCase: ServerLaunchUseCase
    @EnvironmentObject private var generalSettings: GeneralSettingsManager

    private var normalizedServerId: String {
        serverId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var serverName: String {
        serverRepository.getServer(by: normalizedServerId)?.name ?? "server.window.title".localized()
    }

    private var canRenderServerDetail: Bool {
        !normalizedServerId.isEmpty && serverRepository.getServer(by: normalizedServerId) != nil
    }

    private var windowTitle: String {
        canRenderServerDetail ? serverName : "server.window.picker.title".localized()
    }

    var body: some View {
        Group {
            if canRenderServerDetail {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    ContentView()
                        .navigationSplitViewColumnWidth(min: 235, ideal: 235, max: 280)
                } detail: {
                    DetailView()
                }
            } else {
                serverPickerView
            }
        }
        .environmentObject(filterState)
        .environmentObject(detailState)
        .environmentObject(serverRepository)
        .environmentObject(serverNodeRepository)
        .environmentObject(serverLaunchUseCase)
        .environmentObject(generalSettings)
        .toolbar {
            if canRenderServerDetail {
                DetailToolbarView(
                    filterState: filterState,
                    detailState: detailState,
                    serverRepository: serverRepository,
                    serverLaunchUseCase: serverLaunchUseCase
                )
            }
        }
        .windowIdentifierConfig(for: .serverDetail)
        .background(
            WindowAccessor(synchronous: false) { window in
                hostWindow = window
                updateWindowTitle()
            }
        )
        .onAppear {
            syncSelection()
            updateWindowTitle()
        }
        .onChange(of: serverName) { _, _ in
            updateWindowTitle()
        }
        .onChange(of: canRenderServerDetail) { _, _ in
            updateWindowTitle()
        }
        .onChange(of: normalizedServerId) { _, _ in
            updateWindowTitle()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSWindow.didBecomeMainNotification)
        ) { _ in
            updateWindowTitle()
        }
        .onChange(of: coordinator.preferredSections) { _, _ in
            syncSelection()
        }
    }

    private func updateWindowTitle() {
        hostWindow?.title = windowTitle
    }

    private func syncSelection() {
        guard canRenderServerDetail else { return }
        detailState.selectedItem = .server(normalizedServerId)
        detailState.serverId = normalizedServerId
        detailState.serverPanelSection = coordinator.consumePreferredSection(for: normalizedServerId)
    }

    private var serverPickerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("server.window.picker.title".localized())
                .font(.headline)
            List(serverRepository.servers) { server in
                Button {
                    coordinator.open(serverId: server.id, preferredSection: "console")
                    hostWindow?.close()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: server.resolvedIconName)
                            .foregroundStyle(.secondary)
                        Text(server.name)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
        }
        .padding(12)
    }
}

#Preview {
    ServerDetailWindowView(serverId: "preview")
        .environmentObject(ServerRepository())
        .environmentObject(ServerNodeRepository())
        .environmentObject(ServerLaunchUseCase())
        .environmentObject(GeneralSettingsManager.shared)
}
