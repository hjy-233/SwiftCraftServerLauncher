import SwiftUI
import AppKit

/// 侧边栏：游戏列表与资源列表导航
public struct SidebarView: View {
    @EnvironmentObject var detailState: ResourceDetailState
    @EnvironmentObject var serverRepository: ServerRepository
    @EnvironmentObject var serverNodeRepository: ServerNodeRepository
    @EnvironmentObject private var commandPalette: CommandPaletteController
    @AppStorage("activeServerNodeId")
    private var activeServerNodeId: String = ServerNode.local.id
    @StateObject private var serverActionManager = ServerActionManager.shared
    @StateObject private var generalSettings = GeneralSettingsManager.shared
    @StateObject private var downloadCenter = DownloadCenter.shared
    @StateObject private var serverStatusManager = ServerStatusManager.shared
    @State private var showDownloadTip = false
    @State private var isHoveringDownloadBar = false
    @State private var hoveredNodeInfoId: String?
    @State private var hoveredNodePopoverId: String?
    @State private var pendingNodePopoverClose: DispatchWorkItem?
    @State private var pendingDeleteServer: ServerInstance?
    @State private var pendingDeleteServers: [ServerInstance] = []
    @State private var pendingDeleteCorruptedServerName: String?
    @State private var selectedSidebarItems: Set<SidebarItem> = []
    @State private var previousSidebarSelection: Set<SidebarItem> = []

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                CommandPaletteSearchField {
                    commandPalette.present()
                }
                .frame(height: 28)
                Text("⌘K")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.18))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            List(selection: $selectedSidebarItems) {
                Section(header: Text("sidebar.nodes.title".localized())) {
                    ForEach(filteredNodes) { node in
                        HStack(spacing: 6) {
                            Button {
                                activeServerNodeId = node.id
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: node.isLocal ? "desktopcomputer" : "network")
                                    Text(node.name)
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    if activeServerNodeId == node.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.accentColor)
                                            .transition(.opacity.combined(with: .scale))
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 2)
                                .padding(.horizontal, 2)
                                .contentShape(Rectangle())
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(activeServerNodeId == node.id ? Color.accentColor.opacity(0.14) : Color.clear)
                                )
                                .animation(.easeInOut(duration: 0.15), value: activeServerNodeId)
                            }
                            .buttonStyle(.plain)

                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                                .onHover { hovering in
                                    if hovering {
                                        pendingNodePopoverClose?.cancel()
                                        hoveredNodeInfoId = node.id
                                    } else {
                                        scheduleNodePopoverClose(for: node.id)
                                    }
                                }
                                .popover(
                                    isPresented: Binding(
                                        get: { hoveredNodeInfoId == node.id || hoveredNodePopoverId == node.id },
                                        set: { showing in
                                            if !showing, hoveredNodeInfoId == node.id {
                                                hoveredNodeInfoId = nil
                                            }
                                        }
                                    ),
                                    arrowEdge: .trailing
                                ) {
                                    nodeInfoPopover(node: node)
                                        .frame(width: 420)
                                        .padding(10)
                                        .onHover { hovering in
                                            if hovering {
                                                pendingNodePopoverClose?.cancel()
                                                hoveredNodePopoverId = node.id
                                            } else {
                                                hoveredNodePopoverId = nil
                                                scheduleNodePopoverClose(for: node.id)
                                            }
                                        }
                                }
                        }
                        .tag(SidebarItem.node(node.id))
                        .contextMenu {
                            if !node.isLocal {
                                Button(role: .destructive) {
                                    serverNodeRepository.deleteNode(id: node.id)
                                    if activeServerNodeId == node.id {
                                        activeServerNodeId = ServerNode.local.id
                                    }
                                } label: {
                                    Label("node.delete".localized(), systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                // 资源部分
                Section(header: Text("sidebar.resources.title".localized())) {
                    ForEach([ResourceType.mod, ResourceType.plugin], id: \.self) { type in
                        NavigationLink(value: SidebarItem.resource(type)) {
                            HStack(spacing: 6) {
                                Label(type.localizedName, systemImage: type.systemImage)
                            }
                        }
                        .tag(SidebarItem.resource(type))
                    }
                }

                Section(header: Text("\("sidebar.servers.title".localized()) (\(filteredServers.count))")) {
                    ForEach(filteredServers) { server in
                        HStack(spacing: 6) {
                            if let iconURL = server.iconFileURL,
                               let iconImage = NSImage(contentsOf: iconURL) {
                                Image(nsImage: iconImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 16, height: 16)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            } else {
                                Image(systemName: server.resolvedIconName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 16, height: 16)
                                    .foregroundStyle(.secondary)
                            }
                            Text(server.name)
                                .lineLimit(1)
                            Spacer()
                            if serverStatusManager.isServerRunning(serverId: server.id) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .tag(SidebarItem.server(server.id))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handleServerTap(serverId: server.id)
                        }
                        .contextMenu {
                            Button {
                                ServerDetailWindowCoordinator.shared.open(serverId: server.id)
                            } label: {
                                Label("sidebar.context_menu.open_in_new_window".localized(), systemImage: "macwindow")
                            }

                            Button(role: .destructive) {
                                let selectedServers = selectedSidebarItems.compactMap { item -> ServerInstance? in
                                    guard case .server(let id) = item else { return nil }
                                    return serverRepository.getServer(by: id)
                                }
                                let targets = selectedServers.isEmpty ? [server] : selectedServers
                                if generalSettings.confirmDeleteServer {
                                    if targets.count > 1 {
                                        pendingDeleteServers = targets
                                    } else {
                                        pendingDeleteServer = targets.first
                                    }
                                } else {
                                    targets.forEach { target in
                                        serverActionManager.deleteServer(
                                            server: target,
                                            serverRepository: serverRepository,
                                            serverNodeRepository: serverNodeRepository,
                                            selectedItem: detailState.selectedItemBinding
                                        )
                                    }
                                }
                            } label: {
                                Label("sidebar.context_menu.delete_game".localized(), systemImage: "trash")
                            }
                        }
                    }
                    if filteredServers.isEmpty {
                        Text("node.no_servers".localized())
                            .foregroundColor(.secondary)
                    }
                }

                if !filteredCorruptedServers.isEmpty {
                    Section(header: Text("sidebar.corrupted_servers.title".localized())) {
                        ForEach(filteredCorruptedServers, id: \.self) { name in
                            HStack(spacing: 6) {
                                Label(name, systemImage: "exclamationmark.triangle")
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    if generalSettings.confirmDeleteServer {
                                        pendingDeleteCorruptedServerName = name
                                    } else {
                                        serverActionManager.deleteCorruptedServer(
                                            name: name,
                                            serverRepository: serverRepository
                                        )
                                    }
                                } label: {
                                    Label("sidebar.context_menu.delete_game".localized(), systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)
                .opacity(isHoveringDownloadBar ? 1 : 0)
                .animation(.easeInOut(duration: 0.12), value: isHoveringDownloadBar)

            downloadBar
        }
        .onAppear {
            serverRepository.reloadServers()
            if serverNodeRepository.getNode(by: activeServerNodeId) == nil {
                activeServerNodeId = ServerNode.local.id
            }
            syncSidebarSelection(with: detailState.selectedItem)
        }
        .onChange(of: selectedSidebarItems) { _, newValue in
            let added = newValue.subtracting(previousSidebarSelection)
            if let newlySelected = added.first {
                if detailState.selectedItem != newlySelected {
                    detailState.selectedItem = newlySelected
                }
            } else if newValue.count == 1, let only = newValue.first, detailState.selectedItem != only {
                detailState.selectedItem = only
            }
            previousSidebarSelection = newValue
        }
        .onChange(of: detailState.selectedItem) { _, newValue in
            if case .node(let nodeId) = newValue {
                activeServerNodeId = nodeId
            }
            syncSidebarSelection(with: newValue)
        }
        .confirmationDialog(
            "sidebar.confirm.delete_server.title".localized(),
            isPresented: Binding(
                get: { pendingDeleteServer != nil },
                set: { showing in
                    if !showing { pendingDeleteServer = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("common.delete".localized(), role: .destructive) {
                guard let server = pendingDeleteServer else { return }
                serverActionManager.deleteServer(
                    server: server,
                    serverRepository: serverRepository,
                    serverNodeRepository: serverNodeRepository,
                    selectedItem: detailState.selectedItemBinding
                )
                pendingDeleteServer = nil
            }
            Button("common.cancel".localized(), role: .cancel) {
                pendingDeleteServer = nil
            }
        } message: {
            Text(String(format: "sidebar.confirm.delete_server.message".localized(), pendingDeleteServer?.name ?? ""))
        }
        .confirmationDialog(
            "sidebar.confirm.delete_server.title".localized(),
            isPresented: Binding(
                get: { !pendingDeleteServers.isEmpty },
                set: { showing in
                    if !showing { pendingDeleteServers = [] }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("common.delete".localized(), role: .destructive) {
                let targets = pendingDeleteServers
                targets.forEach { target in
                    serverActionManager.deleteServer(
                        server: target,
                        serverRepository: serverRepository,
                        serverNodeRepository: serverNodeRepository,
                        selectedItem: detailState.selectedItemBinding
                    )
                }
                pendingDeleteServers = []
            }
            Button("common.cancel".localized(), role: .cancel) {
                pendingDeleteServers = []
            }
        } message: {
            let names = pendingDeleteServers.map(\.name).joined(separator: ", ")
            Text(String(format: "sidebar.confirm.delete_server.message".localized(), names))
        }
        .confirmationDialog(
            "sidebar.confirm.delete_corrupted_server.title".localized(),
            isPresented: Binding(
                get: { pendingDeleteCorruptedServerName != nil },
                set: { showing in
                    if !showing { pendingDeleteCorruptedServerName = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("common.delete".localized(), role: .destructive) {
                guard let name = pendingDeleteCorruptedServerName else { return }
                serverActionManager.deleteCorruptedServer(name: name, serverRepository: serverRepository)
                pendingDeleteCorruptedServerName = nil
            }
            Button("common.cancel".localized(), role: .cancel) {
                pendingDeleteCorruptedServerName = nil
            }
        } message: {
            Text(String(format: "sidebar.confirm.delete_corrupted_server.message".localized(), pendingDeleteCorruptedServerName ?? ""))
        }
    }

    private func handleServerTap(serverId: String) {
        let item = SidebarItem.server(serverId)
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) {
            if selectedSidebarItems.contains(item) {
                selectedSidebarItems.remove(item)
            } else {
                selectedSidebarItems.insert(item)
                detailState.selectedItem = item
            }
            previousSidebarSelection = selectedSidebarItems
            return
        }
        if modifiers.contains(.shift) {
            if selectedSidebarItems.isEmpty {
                selectedSidebarItems = [item]
            } else {
                selectedSidebarItems.insert(item)
            }
            detailState.selectedItem = item
            previousSidebarSelection = selectedSidebarItems
            return
        }
        selectedSidebarItems = [item]
        previousSidebarSelection = selectedSidebarItems
        detailState.selectedItem = item
    }

    private func syncSidebarSelection(with newValue: SidebarItem) {
        switch newValue {
        case .server:
            if !selectedSidebarItems.contains(newValue) {
                selectedSidebarItems.insert(newValue)
            }
        default:
            if selectedSidebarItems != [newValue] {
                selectedSidebarItems = [newValue]
            }
        }
        previousSidebarSelection = selectedSidebarItems
    }

    private var downloadBar: some View {
        let progress = downloadCenter.averageProgress
        let resolvedProgress = min(max(progress ?? 0, 0), 1)
        let activeCount = downloadCenter.activeTasks.count
        return Button {
            showDownloadTip.toggle()
        } label: {
            HStack(spacing: 10) {
                progressRing(value: resolvedProgress, badgeCount: activeCount)
                Text("\(Int(resolvedProgress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHoveringDownloadBar = hovering
        }
        .popover(isPresented: $showDownloadTip, arrowEdge: .bottom) {
            DownloadCenterTipView()
        }
    }

    private func progressRing(value: Double, badgeCount: Int) -> some View {
        let clampedValue = min(max(value, 0), 1)
        return ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.35), lineWidth: 3)
            Circle()
                .trim(from: 0, to: clampedValue)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 18, height: 18)
        .overlay(alignment: .topTrailing) {
            if badgeCount > 0 {
                Text("\(badgeCount)")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor))
                    .offset(x: 6, y: -6)
            }
        }
    }

    @ViewBuilder
    private func nodeInfoPopover(node: ServerNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(node.name)
                .font(.headline)
            Text(node.isLocal ? "node.type.local".localized() : "node.type.remote_linux".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            row("node.info.host".localized(), node.host)
            row("node.info.user".localized(), node.username)
            row("node.info.port".localized(), "\(node.port)")
            row("node.info.remote_root".localized(), node.remoteRootPath, canCopy: true)
            row("node.info.storage".localized(), AppPaths.remoteNodeDirectory(nodeId: node.id).path, canOpen: true)
        }
    }

    @ViewBuilder
    private func row(_ key: String, _ value: String, canCopy: Bool = false, canOpen: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .foregroundStyle(.secondary)
                .frame(width: 108, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
            Spacer(minLength: 0)
            if canCopy {
                Button("sidebar.node.copy".localized()) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                }
                .buttonStyle(.plain)
            } else if canOpen {
                Button("sidebar.node.open".localized()) {
                    guard FileManager.default.fileExists(atPath: value) else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: value)])
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var filteredServers: [ServerInstance] {
        let nodeServers = serverRepository.servers.filter { $0.nodeId == activeServerNodeId }
        return nodeServers
    }

    private var filteredNodes: [ServerNode] {
        serverNodeRepository.nodes
    }

    private var filteredCorruptedServers: [String] {
        serverRepository.corruptedServers
    }

    private func scheduleNodePopoverClose(for nodeId: String) {
        pendingNodePopoverClose?.cancel()
        let work = DispatchWorkItem {
            if hoveredNodeInfoId == nodeId, hoveredNodePopoverId == nil {
                hoveredNodeInfoId = nil
            }
            if hoveredNodePopoverId == nodeId {
                hoveredNodePopoverId = nil
            }
        }
        pendingNodePopoverClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
}
