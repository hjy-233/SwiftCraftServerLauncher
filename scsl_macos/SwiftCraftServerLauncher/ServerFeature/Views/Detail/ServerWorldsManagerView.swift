import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ServerWorldsManagerView: View {
    let server: ServerInstance
    @EnvironmentObject var serverNodeRepository: ServerNodeRepository
    @StateObject private var generalSettings = GeneralSettingsManager.shared
    @State private var folders: [URL] = []
    @State private var remoteFolders: [String] = []
    @State private var showImporter = false
    @State private var pendingLocalRemoveURL: URL?
    @State private var pendingRemoteRemoveName: String?
    @State private var selectedWorldId: String?
    @StateObject private var toolbarSelection = ServerDetailToolbarSelectionState.shared
    private let autoRefreshTimer = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    var body: some View {
        ServerDetailPage(
            title: "server.worlds.title".localized()
        ) {
            if isRemoteServer ? remoteFolders.isEmpty : folders.isEmpty {
                ServerDetailEmptyState(text: "common.empty".localized())
            } else {
                List(selection: $selectedWorldId) {
                    if isRemoteServer {
                        ForEach(remoteFolders, id: \.self) { name in
                            row(title: name)
                                .tag(name)
                        }
                    } else {
                        ForEach(folders, id: \.self) { url in
                            row(title: url.lastPathComponent)
                                .tag(url.path)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear { loadFolders() }
        .onReceive(autoRefreshTimer) { _ in
            loadFolders()
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                importWorlds(urls)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverDetailToolbarAction)) { note in
            guard let action = ServerDetailToolbarActionBus.action(from: note) else { return }
            switch action {
            case .worldsOpenFolder:
                openFolder()
            case .worldsImport:
                showImporter = true
            case .worldsRemove:
                confirmSelectedRemoval()
            default:
                break
            }
        }
        .onChange(of: selectedWorldId) { _, newValue in
            toolbarSelection.selectedWorldIdByServerId[server.id] = newValue
        }
        .onDisappear {
            toolbarSelection.selectedWorldIdByServerId[server.id] = nil
        }
        .confirmationDialog(
            "server.worlds.remove.title".localized(),
            isPresented: Binding(
                get: { pendingLocalRemoveURL != nil || pendingRemoteRemoveName != nil },
                set: { showing in
                    if !showing {
                        pendingLocalRemoveURL = nil
                        pendingRemoteRemoveName = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("common.delete".localized(), role: .destructive) {
                if let url = pendingLocalRemoveURL {
                    removeFolder(url)
                } else if let name = pendingRemoteRemoveName {
                    removeRemoteFolder(name)
                }
                pendingLocalRemoveURL = nil
                pendingRemoteRemoveName = nil
            }
            Button("common.cancel".localized(), role: .cancel) {
                pendingLocalRemoveURL = nil
                pendingRemoteRemoveName = nil
            }
        } message: {
            if let url = pendingLocalRemoveURL {
                Text(String(format: "server.worlds.remove.message".localized(), url.lastPathComponent))
            } else {
                Text(String(format: "server.worlds.remove.message".localized(), pendingRemoteRemoveName ?? ""))
            }
        }
    }

    private func row(title: String) -> some View {
        Label {
            Text(title)
                .lineLimit(1)
        } icon: {
            Image(systemName: "globe.americas")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var isRemoteServer: Bool {
        server.nodeId != ServerNode.local.id || server.javaPath == "java"
    }

    private func worldDir() -> URL {
        AppPaths.serverDirectory(serverName: server.directoryName)
    }

    private func loadFolders() {
        if isRemoteServer {
            Task {
                guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
                if let list = try? await SSHNodeService.listRemoteWorlds(node: node, serverName: server.name) {
                    await MainActor.run {
                        remoteFolders = list
                        if let selectedWorldId, !list.contains(selectedWorldId) {
                            self.selectedWorldId = nil
                        }
                    }
                }
            }
            return
        }
        let dir = worldDir()
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        folders = urls.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        }
        .filter { $0.lastPathComponent.hasPrefix("world") }
        if let selectedWorldId, !folders.contains(where: { $0.path == selectedWorldId }) {
            self.selectedWorldId = nil
        }
    }

    private func confirmSelectedRemoval() {
        guard let selectedWorldId else { return }
        if isRemoteServer {
            if generalSettings.confirmDeleteWorld {
                pendingRemoteRemoveName = selectedWorldId
            } else {
                removeRemoteFolder(selectedWorldId)
            }
            return
        }
        guard let url = folders.first(where: { $0.path == selectedWorldId }) else { return }
        if generalSettings.confirmDeleteWorld {
            pendingLocalRemoveURL = url
        } else {
            removeFolder(url)
        }
    }

    private func removeFolder(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        if selectedWorldId == url.path {
            selectedWorldId = nil
        }
        loadFolders()
    }

    private func openFolder() {
        if isRemoteServer { return }
        let dir = worldDir()
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
    }

    private func importWorlds(_ urls: [URL]) {
        if isRemoteServer {
            guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
            Task {
                for url in urls {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }
                    do {
                        try await SSHNodeService.uploadRemoteWorldDirectory(node: node, serverName: server.name, localURL: url)
                    } catch {
                        await MainActor.run { GlobalErrorHandler.shared.handle(error) }
                    }
                }
                await MainActor.run { loadFolders() }
            }
            return
        }
        let dir = worldDir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            let target = dir.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: target)
            try? FileManager.default.copyItem(at: url, to: target)
        }
        loadFolders()
    }

    private func removeRemoteFolder(_ name: String) {
        guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
        Task {
            do {
                try await SSHNodeService.removeRemoteWorld(node: node, serverName: server.name, worldName: name)
                await MainActor.run {
                    if selectedWorldId == name {
                        selectedWorldId = nil
                    }
                    loadFolders()
                }
            } catch {
                await MainActor.run { GlobalErrorHandler.shared.handle(error) }
            }
        }
    }
}
