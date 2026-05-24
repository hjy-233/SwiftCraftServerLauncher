import SwiftUI
import UniformTypeIdentifiers

struct ServerModsManagerView: View {
    let server: ServerInstance
    @EnvironmentObject var serverNodeRepository: ServerNodeRepository
    @StateObject private var generalSettings = GeneralSettingsManager.shared
    @State private var files: [URL] = []
    @State private var remoteFiles: [String] = []
    @State private var showImporter = false
    @State private var pendingLocalRemoveURL: URL?
    @State private var pendingRemoteRemoveFileName: String?
    @State private var selectedFileId: String?
    @StateObject private var toolbarSelection = ServerDetailToolbarSelectionState.shared
    private let autoRefreshTimer = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    var body: some View {
        ServerDetailPage(
            title: "server.mods.title".localized()
        ) {
            if isRemoteServer ? remoteFiles.isEmpty : files.isEmpty {
                ServerDetailEmptyState(text: "common.empty".localized())
            } else {
                List(selection: $selectedFileId) {
                    if isRemoteServer {
                        ForEach(remoteFiles, id: \.self) { fileName in
                            row(title: fileName)
                                .tag(fileName)
                        }
                    } else {
                        ForEach(files, id: \.self) { url in
                            row(title: url.lastPathComponent)
                                .tag(url.path)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear { loadFiles() }
        .onReceive(autoRefreshTimer) { _ in
            loadFiles()
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [UTType(filenameExtension: "jar") ?? .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                addFiles(urls)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverDetailToolbarAction)) { note in
            guard let action = ServerDetailToolbarActionBus.action(from: note) else { return }
            if action == .modsImport {
                showImporter = true
            } else if action == .modsRemove {
                confirmSelectedRemoval()
            }
        }
        .onChange(of: selectedFileId) { _, newValue in
            toolbarSelection.selectedModIdByServerId[server.id] = newValue
        }
        .onDisappear {
            toolbarSelection.selectedModIdByServerId[server.id] = nil
        }
        .confirmationDialog(
            "server.mods.remove.title".localized(),
            isPresented: Binding(
                get: { pendingLocalRemoveURL != nil || pendingRemoteRemoveFileName != nil },
                set: { showing in
                    if !showing {
                        pendingLocalRemoveURL = nil
                        pendingRemoteRemoveFileName = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("common.remove".localized(), role: .destructive) {
                if let url = pendingLocalRemoveURL {
                    removeFile(url)
                } else if let fileName = pendingRemoteRemoveFileName {
                    removeRemoteFile(fileName)
                }
                pendingLocalRemoveURL = nil
                pendingRemoteRemoveFileName = nil
            }
            Button("common.cancel".localized(), role: .cancel) {
                pendingLocalRemoveURL = nil
                pendingRemoteRemoveFileName = nil
            }
        } message: {
            if let url = pendingLocalRemoveURL {
                Text(String(format: "server.mods.remove.message".localized(), url.lastPathComponent))
            } else {
                Text(String(format: "server.mods.remove.message".localized(), pendingRemoteRemoveFileName ?? ""))
            }
        }
    }

    private func row(title: String) -> some View {
        Label {
            Text(title)
                .lineLimit(1)
        } icon: {
            Image(systemName: "shippingbox")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var isRemoteServer: Bool {
        server.nodeId != ServerNode.local.id || server.javaPath == "java"
    }

    private func modsDir() -> URL {
        AppPaths.serverModsDirectory(serverName: server.name)
    }

    private func loadFiles() {
        if isRemoteServer {
            guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
            Task {
                do {
                    let list = try await SSHNodeService.listRemoteMods(node: node, serverName: server.name)
                    await MainActor.run {
                        remoteFiles = list
                        if let selectedFileId, !list.contains(selectedFileId) {
                            self.selectedFileId = nil
                        }
                    }
                } catch {
                    await MainActor.run { GlobalErrorHandler.shared.handle(error) }
                }
            }
            return
        }
        let dir = modsDir()
        let all = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        files = all.filter { $0.pathExtension.lowercased() == "jar" }
        if let selectedFileId, !files.contains(where: { $0.path == selectedFileId }) {
            self.selectedFileId = nil
        }
    }

    private func confirmSelectedRemoval() {
        guard let selectedFileId else { return }
        if isRemoteServer {
            if generalSettings.confirmUninstallPluginMod {
                pendingRemoteRemoveFileName = selectedFileId
            } else {
                removeRemoteFile(selectedFileId)
            }
            return
        }
        guard let url = files.first(where: { $0.path == selectedFileId }) else { return }
        if generalSettings.confirmUninstallPluginMod {
            pendingLocalRemoveURL = url
        } else {
            removeFile(url)
        }
    }

    private func addFiles(_ urls: [URL]) {
        if isRemoteServer {
            guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
            Task {
                for url in urls where url.pathExtension.lowercased() == "jar" {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }
                    do {
                        try await SSHNodeService.uploadRemoteMod(node: node, serverName: server.name, localURL: url)
                    } catch {
                        await MainActor.run { GlobalErrorHandler.shared.handle(error) }
                    }
                }
                await MainActor.run { loadFiles() }
            }
            return
        }
        let dir = modsDir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            guard url.pathExtension.lowercased() == "jar" else { continue }
            let target = dir.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: target)
            try? FileManager.default.copyItem(at: url, to: target)
        }
        loadFiles()
    }

    private func removeFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        if selectedFileId == url.path {
            selectedFileId = nil
        }
        loadFiles()
    }

    private func removeRemoteFile(_ fileName: String) {
        guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
        Task {
            do {
                try await SSHNodeService.removeRemoteMod(node: node, serverName: server.name, fileName: fileName)
                await MainActor.run {
                    if selectedFileId == fileName {
                        selectedFileId = nil
                    }
                    loadFiles()
                }
            } catch {
                await MainActor.run { GlobalErrorHandler.shared.handle(error) }
            }
        }
    }
}
