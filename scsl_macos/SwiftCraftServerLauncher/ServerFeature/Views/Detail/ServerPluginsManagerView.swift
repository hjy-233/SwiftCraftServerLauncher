import SwiftUI
import UniformTypeIdentifiers

struct ServerPluginsManagerView: View {
    let server: ServerInstance
    @EnvironmentObject var serverNodeRepository: ServerNodeRepository
    @StateObject private var generalSettings = GeneralSettingsManager.shared
    @State private var files: [URL] = []
    @State private var remoteFiles: [String] = []
    @State private var showImporter = false
    @State private var pendingLocalRemoveURL: URL?
    @State private var pendingRemoteRemoveFileName: String?
    private let autoRefreshTimer = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    var body: some View {
        ServerDetailPage(
            title: "server.plugins.title".localized()
        ) {
            if isRemoteServer ? remoteFiles.isEmpty : files.isEmpty {
                ServerDetailEmptyState(text: "common.empty".localized())
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if isRemoteServer {
                            ForEach(Array(remoteFiles.enumerated()), id: \.offset) { index, fileName in
                                row(title: fileName) {
                                    if generalSettings.confirmUninstallPluginMod {
                                        pendingRemoteRemoveFileName = fileName
                                    } else {
                                        removeRemoteFile(fileName)
                                    }
                                }
                                if index < remoteFiles.count - 1 {
                                    Divider()
                                }
                            }
                        } else {
                            ForEach(Array(files.enumerated()), id: \.offset) { index, url in
                                row(title: url.lastPathComponent) {
                                    if generalSettings.confirmUninstallPluginMod {
                                        pendingLocalRemoveURL = url
                                    } else {
                                        removeFile(url)
                                    }
                                }
                                if index < files.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
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
            if action == .pluginsImport {
                showImporter = true
            }
        }
        .confirmationDialog(
            "server.plugins.remove.title".localized(),
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
                Text(String(format: "server.plugins.remove.message".localized(), url.lastPathComponent))
            } else {
                Text(String(format: "server.plugins.remove.message".localized(), pendingRemoteRemoveFileName ?? ""))
            }
        }
    }

    private func row(title: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer()
            Button("common.remove".localized(), action: onRemove)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }

    private var isRemoteServer: Bool {
        server.nodeId != ServerNode.local.id || server.javaPath == "java"
    }

    private func pluginsDir() -> URL {
        AppPaths.serverPluginsDirectory(serverName: server.name)
    }

    private func loadFiles() {
        if isRemoteServer {
            guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
            Task {
                do {
                    let list = try await SSHNodeService.listRemotePlugins(node: node, serverName: server.name)
                    await MainActor.run { remoteFiles = list }
                } catch {
                    await MainActor.run { GlobalErrorHandler.shared.handle(error) }
                }
            }
            return
        }
        let dir = pluginsDir()
        let all = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        files = all.filter { $0.pathExtension.lowercased() == "jar" }
    }

    private func addFiles(_ urls: [URL]) {
        if isRemoteServer {
            guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
            Task {
                for url in urls where url.pathExtension.lowercased() == "jar" {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }
                    do {
                        try await SSHNodeService.uploadRemotePlugin(node: node, serverName: server.name, localURL: url)
                    } catch {
                        await MainActor.run { GlobalErrorHandler.shared.handle(error) }
                    }
                }
                await MainActor.run { loadFiles() }
            }
            return
        }
        let dir = pluginsDir()
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
        loadFiles()
    }

    private func removeRemoteFile(_ fileName: String) {
        guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
        Task {
            do {
                try await SSHNodeService.removeRemotePlugin(node: node, serverName: server.name, fileName: fileName)
                await MainActor.run { loadFiles() }
            } catch {
                await MainActor.run { GlobalErrorHandler.shared.handle(error) }
            }
        }
    }
}
