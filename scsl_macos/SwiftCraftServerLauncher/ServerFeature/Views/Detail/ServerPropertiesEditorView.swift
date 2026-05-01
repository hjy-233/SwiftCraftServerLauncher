import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ServerFileItem: Identifiable, Hashable {
    let url: URL?
    let relativePath: String
    let isDirectory: Bool
    let fileSize: Int?

    var id: String { relativePath }
    var fileName: String { URL(fileURLWithPath: relativePath).lastPathComponent }
    var folderPath: String {
        let folder = URL(fileURLWithPath: relativePath).deletingLastPathComponent().path
        if folder == "." || folder == "/" {
            return ""
        }
        return folder
    }
    var pathComponents: [String] {
        relativePath.split(separator: "/").map(String.init)
    }
}

private struct ServerConfigTreeNode: Identifiable, Hashable {
    enum Kind: Hashable {
        case folder
        case file(ServerFileItem)
    }

    let id: String
    var name: String
    var kind: Kind
    var children: [Self]?

    var isFolder: Bool {
        if case .folder = kind { return true }
        return false
    }
}

private enum FileEditingMode: Equatable {
    case idle
    case newFile
    case newFolder
    case rename(ServerFileItem)
}

private enum EditingField: Hashable {
    case newFile
    case newFolder
    case rename(String)
}

struct ServerPropertiesEditorView: View {
    let server: ServerInstance
    @EnvironmentObject var serverNodeRepository: ServerNodeRepository
    @StateObject private var serverActionManager = ServerActionManager.shared
    @StateObject private var generalSettings = GeneralSettingsManager.shared
    @State var properties: [String: String] = [:]
    @State private var isLoaded = false
    @State var isDirty = false
    @State var searchText: String = ""
    @State private var fileItems: [ServerFileItem] = []
    @State private var selectedFile: ServerFileItem?
    @State private var selectedNodeId: String?
    @State private var serverPropertiesMode: ServerPropertiesMode = .visual
    @State private var showSidebar = true
    @State private var isImportingFiles = false
    @State private var editingMode: FileEditingMode = .idle
    @State private var editingName = ""
    @FocusState private var editingField: EditingField?
    @State private var showDeleteConfirm = false
    @State private var deleteTarget: ServerFileItem?
    @State var propertiesAutoSaveTask: Task<Void, Never>?
    private let autoRefreshTimer = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    private let editableExtensions = Set(["properties", "yml", "yaml", "toml", "json", "conf", "cfg", "ini", "txt", "log", "md"])

    var body: some View {
        let page = ServerDetailPage(
            title: "server.properties.title".localized(),
            contentPadding: 0,
            actions: {
                if generalSettings.serverFileManagerShowShortcuts {
                    shortcutBar
                } else {
                    EmptyView()
                }
            },
            content: {
                HSplitView {
                    if showSidebar {
                        configSidebar
                    }
                    contentArea
                }
            }
        )
        let baseView = page
            .background(shortcutCommandPanel)
            .fileImporter(
                isPresented: $isImportingFiles,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    importFiles(urls, to: currentDirectoryPath)
                case .failure(let error):
                    GlobalErrorHandler.shared.handle(error)
                }
            }
        let lifecycleView = baseView
            .alert("server.files.delete".localized(), isPresented: $showDeleteConfirm) {
                Button("common.delete".localized(), role: .destructive) { deleteSelected() }
                Button("common.cancel".localized(), role: .cancel) {}
            } message: {
                Text("server.files.delete.confirm".localized())
            }
            .onAppear {
                load()
                loadFiles()
            }
            .onReceive(autoRefreshTimer) { _ in
                if !isDirty {
                    load()
                }
                loadFiles()
            }
            .onReceive(NotificationCenter.default.publisher(for: .serverDetailToolbarAction)) { note in
                guard let action = ServerDetailToolbarActionBus.action(from: note) else { return }
                handleToolbarAction(action)
            }
            .onDisappear {
                propertiesAutoSaveTask?.cancel()
                save()
            }
            .onChange(of: selectedNodeId) { _, newValue in
                guard let newValue, let item = configItemById[newValue] else { return }
                selectedFile = item
            }
            .onChange(of: selectedFile) { _, newValue in
                selectedNodeId = newValue?.id
            }
        return lifecycleView
    }

    private func load() {
        if isRemoteServer {
            Task {
                guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
                do {
                    let remoteProps = try await SSHNodeService.readRemoteServerProperties(node: node, serverName: server.name)
                    await MainActor.run {
                        properties = remoteProps
                        isLoaded = true
                        isDirty = false
                    }
                } catch {
                    await MainActor.run { GlobalErrorHandler.shared.handle(error) }
                }
            }
            return
        }
        Task {
            do {
                let localProps = try await ServerPropertiesService.readProperties(server: server)
                await MainActor.run {
                    properties = localProps
                    isLoaded = true
                    isDirty = false
                }
            } catch {
                await MainActor.run { GlobalErrorHandler.shared.handle(error) }
            }
        }
    }

    func save() {
        if isRemoteServer {
            Task {
                guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
                do {
                    try await SSHNodeService.writeRemoteServerProperties(node: node, serverName: server.name, properties: properties)
                    await MainActor.run { isDirty = false }
                } catch {
                    await MainActor.run { GlobalErrorHandler.shared.handle(error) }
                }
            }
            return
        }
        Task {
            do {
                try await ServerPropertiesService.writeProperties(server: server, properties: properties)
                await MainActor.run { isDirty = false }
            } catch {
                await MainActor.run { GlobalErrorHandler.shared.handle(error) }
            }
        }
    }

    private func loadFiles() {
        if isRemoteServer {
            guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
            Task {
                do {
                    let entries = try await SSHNodeService.listRemoteServerFiles(node: node, serverName: server.name)
                    await MainActor.run {
                        fileItems = entries.map {
                            ServerFileItem(
                                url: nil,
                                relativePath: $0.relativePath,
                                isDirectory: $0.isDirectory,
                                fileSize: nil
                            )
                        }
                        selectDefaultFileIfNeeded()
                    }
                } catch {
                    await MainActor.run { GlobalErrorHandler.shared.handle(error) }
                }
            }
            return
        }
        Task {
            do {
                let items = try await ServerFileService.listFiles(server: server)
                await MainActor.run {
                    fileItems = items
                    selectDefaultFileIfNeeded()
                }
            } catch {
                await MainActor.run { GlobalErrorHandler.shared.handle(error) }
            }
        }
    }

    private func selectDefaultFileIfNeeded() {
        if let selectedFile, fileItems.contains(selectedFile) {
            return
        }
        if let defaultItem = fileItems.first(where: { $0.relativePath.lowercased().hasSuffix("server.properties") }) {
            selectedFile = defaultItem
            selectedNodeId = defaultItem.id
            return
        }
        selectedFile = fileItems.first
        selectedNodeId = fileItems.first?.id
    }

    private var configSidebar: some View {
        List(selection: $selectedNodeId) {
            if editingMode == .newFile || editingMode == .newFolder {
                editingRow(isFolder: editingMode == .newFolder)
            }
            OutlineGroup(configTree, children: \.children) { node in
                let row = HStack(spacing: 8) {
                    Image(systemName: node.isFolder ? "folder" : "doc.text")
                        .foregroundStyle(.secondary)
                    if case .rename(let target) = editingMode, target.id == node.id {
                        TextField("server.files.name_placeholder".localized(), text: $editingName)
                            .textFieldStyle(.plain)
                            .onSubmit { commitEditing() }
                            .focused($editingField, equals: .rename(target.id))
                    } else {
                        Text(node.name)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
                .contextMenu {
                    if let item = itemForNode(node) {
                        Button("server.files.open_in_finder".localized()) {
                            openInFinder(item)
                        }
                        Divider()
                        Button("server.files.rename".localized()) {
                            beginRename(item)
                        }
                        Button("server.files.delete".localized(), role: .destructive) {
                            confirmDelete(item)
                        }
                    }
                    Divider()
                    Button("server.files.upload".localized()) {
                        isImportingFiles = true
                    }
                    Button("server.files.new_folder".localized()) {
                        beginNewFolder()
                    }
                    Button("server.files.new_file".localized()) {
                        beginNewFile()
                    }
                }
                let droppableRow: some View = {
                    if node.isFolder {
                        return AnyView(
                            row.onDrop(of: [UTType.fileURL, UTType.plainText], isTargeted: nil) { providers in
                                handleDrop(providers, to: node.id)
                            }
                        )
                    }
                    return AnyView(row)
                }()
                droppableRow
                    .draggable(node.id)
                    .tag(node.id)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [UTType.fileURL, UTType.plainText], isTargeted: nil) { providers in
            handleDrop(providers, to: "")
        }
        .contextMenu {
            Button("server.files.open_in_finder".localized()) {
                serverActionManager.showInFinder(server: server)
            }
            Divider()
            Button("server.files.upload".localized()) {
                isImportingFiles = true
            }
            Button("server.files.new_folder".localized()) {
                beginNewFolder()
            }
            Button("server.files.new_file".localized()) {
                beginNewFile()
            }
        }
        .frame(minWidth: 150, idealWidth: 190, maxWidth: 260, maxHeight: .infinity)
    }

    private var contentArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selectedFile, selectedFile.isDirectory {
                folderDetailView(for: selectedFile)
            } else if let selectedFile, selectedFile.relativePath.lowercased().hasSuffix("server.properties") {
                Picker("", selection: $serverPropertiesMode) {
                    Text("server.properties.mode.visual".localized())
                        .tag(ServerPropertiesMode.visual)
                    Text("server.properties.mode.raw".localized())
                        .tag(ServerPropertiesMode.raw)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)

                if serverPropertiesMode == .visual {
                    serverPropertiesVisualEditor
                } else {
                    RawConfigEditorView(server: server, item: selectedFile)
                        .environmentObject(serverNodeRepository)
                        .id(selectedFile.id)
                }
            } else if let selectedFile, isEditableFile(selectedFile) {
                RawConfigEditorView(server: server, item: selectedFile)
                    .environmentObject(serverNodeRepository)
                    .id(selectedFile.id)
            } else if selectedFile != nil {
                ServerDetailEmptyState(text: "server.files.not_editable".localized())
            } else {
                ServerDetailEmptyState(text: "server.extra_configs.empty".localized())
            }
        }
        .padding(.leading, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func folderDetailView(for item: ServerFileItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.fileName)
                .font(.title3.weight(.semibold))
            Text("server.files.folder_hint".localized())
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDrop(of: [UTType.fileURL, UTType.plainText], isTargeted: nil) { providers in
            handleDrop(providers, to: item.relativePath)
        }
    }

    private var serverPropertiesVisualEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("common.search".localized(), text: $searchText)
                .textFieldStyle(.roundedBorder)

            if properties.isEmpty && isLoaded {
                ServerDetailEmptyState(text: "server.properties.no_properties".localized())
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredKeys, id: \.self) { key in
                            propertyRow(key: key)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var configTree: [ServerConfigTreeNode] {
        var root: [String: ServerConfigTreeNode] = [:]
        for item in fileItems {
            insert(item: item, into: &root)
        }
        return root.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var configItemById: [String: ServerFileItem] {
        Dictionary(uniqueKeysWithValues: fileItems.map { ($0.id, $0) })
    }

    private func insert(item: ServerFileItem, into root: inout [String: ServerConfigTreeNode]) {
        let parts = item.pathComponents
        guard !parts.isEmpty else { return }
        insert(parts: parts, index: 0, currentPath: "", item: item, into: &root)
    }

    private func insert(
        parts: [String],
        index: Int,
        currentPath: String,
        item: ServerFileItem,
        into nodeMap: inout [String: ServerConfigTreeNode]
    ) {
        let name = parts[index]
        let path = currentPath.isEmpty ? name : "\(currentPath)/\(name)"
        if index == parts.count - 1 {
            if item.isDirectory {
                let existingChildren = nodeMap[path]?.children
                nodeMap[path] = ServerConfigTreeNode(id: item.id, name: name, kind: .folder, children: existingChildren)
            } else {
                nodeMap[path] = ServerConfigTreeNode(
                    id: item.id,
                    name: name,
                    kind: .file(item),
                    children: nil
                )
            }
            return
        }
        var node = nodeMap[path] ?? ServerConfigTreeNode(id: path, name: name, kind: .folder, children: [])
        if node.children == nil {
            node.children = []
        }
        var childMap = Dictionary(uniqueKeysWithValues: (node.children ?? []).map { ($0.id, $0) })
        insert(parts: parts, index: index + 1, currentPath: path, item: item, into: &childMap)
        node.children = childMap.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        nodeMap[path] = node
    }

    private var isRemoteServer: Bool {
        server.nodeId != ServerNode.local.id
    }

    private var currentDirectoryPath: String {
        if let selectedFile, selectedFile.isDirectory {
            return selectedFile.relativePath
        }
        if let selectedFile {
            return selectedFile.folderPath
        }
        return ""
    }

    private func itemForNode(_ node: ServerConfigTreeNode) -> ServerFileItem? {
        if case .file(let item) = node.kind {
            return item
        }
        return fileItems.first { $0.relativePath == node.id && $0.isDirectory }
    }

    private func isEditableFile(_ item: ServerFileItem) -> Bool {
        guard !item.isDirectory else { return false }
        let ext = URL(fileURLWithPath: item.relativePath).pathExtension.lowercased()
        guard editableExtensions.contains(ext) else { return false }
        if let size = item.fileSize, size > 1_000_000 {
            return false
        }
        return true
    }

    private func handleDrop(_ providers: [NSItemProvider], to targetFolder: String) -> Bool {
        var handled = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { object, _ in
                    guard let url = object else { return }
                    importFiles([url], to: targetFolder)
                }
                handled = true
                continue
            }
            if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let value = object as? String else { return }
                    moveItem(from: value, toFolder: targetFolder)
                }
                handled = true
            }
        }
        return handled
    }

    private func importFiles(_ urls: [URL], to targetFolder: String) {
        if isRemoteServer {
            guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
            Task {
                do {
                    for url in urls {
                        try await SSHNodeService.uploadRemoteFile(node: node, serverName: server.name, localURL: url, remoteDirectory: targetFolder)
                    }
                    await MainActor.run { loadFiles() }
                } catch {
                    await MainActor.run { GlobalErrorHandler.shared.handle(error) }
                }
            }
            return
        }
        Task {
            do {
                for url in urls {
                    try await ServerFileService.importPath(server: server, sourceURL: url, targetDirectory: targetFolder)
                }
                await MainActor.run { loadFiles() }
            } catch {
                await MainActor.run { GlobalErrorHandler.shared.handle(error) }
            }
        }
    }

    private func moveItem(from sourceRelativePath: String, toFolder targetFolder: String) {
        guard sourceRelativePath != targetFolder else { return }
        if !targetFolder.isEmpty && targetFolder.hasPrefix(sourceRelativePath + "/") {
            return
        }
        let sourceName = URL(fileURLWithPath: sourceRelativePath).lastPathComponent
        let targetPath = targetFolder.isEmpty ? sourceName : "\(targetFolder)/\(sourceName)"
        if isRemoteServer {
            guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
            Task {
                do {
                    try await SSHNodeService.moveRemotePath(node: node, serverName: server.name, from: sourceRelativePath, to: targetPath)
                    await MainActor.run { loadFiles() }
                } catch {
                    await MainActor.run { GlobalErrorHandler.shared.handle(error) }
                }
            }
            return
        }
        Task {
            do {
                try await ServerFileService.movePath(server: server, from: sourceRelativePath, to: targetPath)
                await MainActor.run { loadFiles() }
            } catch {
                await MainActor.run { GlobalErrorHandler.shared.handle(error) }
            }
        }
    }

    private func createFolder() {
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let targetPath = currentDirectoryPath.isEmpty ? trimmed : "\(currentDirectoryPath)/\(trimmed)"
        if isRemoteServer {
            guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
            Task {
                do {
                    try await SSHNodeService.createRemoteDirectory(node: node, serverName: server.name, relativePath: targetPath)
                    await MainActor.run {
                        finishEditing()
                        loadFiles()
                    }
                } catch {
                    await MainActor.run { GlobalErrorHandler.shared.handle(error) }
                }
            }
            return
        }
        Task {
            do {
                try await ServerFileService.createDirectory(server: server, relativePath: targetPath)
                await MainActor.run {
                    finishEditing()
                    loadFiles()
                }
            } catch {
                await MainActor.run { GlobalErrorHandler.shared.handle(error) }
            }
        }
    }

    private func createFile() {
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let targetPath = currentDirectoryPath.isEmpty ? trimmed : "\(currentDirectoryPath)/\(trimmed)"
        if isRemoteServer {
            guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
            Task {
                do {
                    try await SSHNodeService.writeRemoteConfigFile(node: node, serverName: server.name, relativePath: targetPath, content: "")
                    await MainActor.run {
                        finishEditing()
                        loadFiles()
                    }
                } catch {
                    await MainActor.run { GlobalErrorHandler.shared.handle(error) }
                }
            }
            return
        }
        Task {
            do {
                try await ServerFileService.createFile(server: server, relativePath: targetPath)
                await MainActor.run {
                    finishEditing()
                    loadFiles()
                }
            } catch {
                await MainActor.run { GlobalErrorHandler.shared.handle(error) }
            }
        }
    }

    private func beginRenameSelected() {
        guard let selectedFile else { return }
        beginRename(selectedFile)
    }

    private func beginRename(_ item: ServerFileItem) {
        editingMode = .rename(item)
        editingName = item.fileName
        DispatchQueue.main.async {
            editingField = .rename(item.id)
        }
    }

    private func renameSelected() {
        guard case .rename(let target) = editingMode else { return }
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let newPath = target.folderPath.isEmpty ? trimmed : "\(target.folderPath)/\(trimmed)"
        if isRemoteServer {
            guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
            Task {
                do {
                    try await SSHNodeService.moveRemotePath(node: node, serverName: server.name, from: target.relativePath, to: newPath)
                    await MainActor.run {
                        finishEditing()
                        loadFiles()
                    }
                } catch {
                    await MainActor.run { GlobalErrorHandler.shared.handle(error) }
                }
            }
            return
        }
        Task {
            do {
                try await ServerFileService.movePath(server: server, from: target.relativePath, to: newPath)
                await MainActor.run {
                    finishEditing()
                    loadFiles()
                }
            } catch {
                await MainActor.run { GlobalErrorHandler.shared.handle(error) }
            }
        }
    }

    private func confirmDeleteSelected() {
        guard let selectedFile else { return }
        confirmDelete(selectedFile)
    }

    private func confirmDelete(_ item: ServerFileItem) {
        deleteTarget = item
        showDeleteConfirm = true
    }

    private func deleteSelected() {
        guard let deleteTarget else { return }
        if isRemoteServer {
            guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
            Task {
                do {
                    try await SSHNodeService.removeRemotePath(node: node, serverName: server.name, relativePath: deleteTarget.relativePath)
                    await MainActor.run {
                        self.deleteTarget = nil
                        loadFiles()
                    }
                } catch {
                    await MainActor.run { GlobalErrorHandler.shared.handle(error) }
                }
            }
            return
        }
        Task {
            do {
                try await ServerFileService.deletePath(server: server, relativePath: deleteTarget.relativePath)
                await MainActor.run {
                    self.deleteTarget = nil
                    loadFiles()
                }
            } catch {
                await MainActor.run { GlobalErrorHandler.shared.handle(error) }
            }
        }
    }

    private func handleToolbarAction(_ action: ServerDetailToolbarAction) {
        switch action {
        case .configToggleSidebar:
            showSidebar.toggle()
        case .configUpload:
            isImportingFiles = true
        case .configNewFolder:
            beginNewFolder()
        case .configNewFile:
            beginNewFile()
        case .configRename:
            beginRenameSelected()
        case .configDelete:
            confirmDeleteSelected()
        default:
            break
        }
    }

    private func openInFinder(_ item: ServerFileItem) {
        if server.nodeId != ServerNode.local.id {
            serverActionManager.showInFinder(server: server)
            return
        }
        let root = AppPaths.serverDirectory(serverName: server.directoryName)
        let targetURL = root.appendingPathComponent(item.relativePath)
        if item.isDirectory {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: targetURL.path)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([targetURL])
        }
    }

    private func beginNewFile() {
        editingMode = .newFile
        editingName = ""
        DispatchQueue.main.async {
            editingField = .newFile
        }
    }

    private func beginNewFolder() {
        editingMode = .newFolder
        editingName = ""
        DispatchQueue.main.async {
            editingField = .newFolder
        }
    }

    private func commitEditing() {
        switch editingMode {
        case .newFile:
            createFile()
        case .newFolder:
            createFolder()
        case .rename:
            renameSelected()
        case .idle:
            break
        }
    }

    private func cancelEditing() {
        editingMode = .idle
        editingName = ""
        editingField = nil
    }

    private func finishEditing() {
        editingMode = .idle
        editingName = ""
        editingField = nil
    }

    private func editingRow(isFolder: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isFolder ? "folder.badge.plus" : "doc.badge.plus")
                .foregroundStyle(.secondary)
            TextField("server.files.name_placeholder".localized(), text: $editingName)
                .textFieldStyle(.plain)
                .onSubmit { commitEditing() }
                .focused($editingField, equals: isFolder ? .newFolder : .newFile)
            Button {
                cancelEditing()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
    }

    private var shortcutCommandPanel: some View {
        ServerPropertiesShortcutCommands(
            showSidebar: $showSidebar,
            isImportingFiles: $isImportingFiles,
            showNewFolderPrompt: Binding(
                get: { editingMode == .newFolder },
                set: { if $0 { beginNewFolder() } else { cancelEditing() } }
            ),
            showNewFilePrompt: Binding(
                get: { editingMode == .newFile },
                set: { if $0 { beginNewFile() } else { cancelEditing() } }
            ),
            beginRenameSelected: beginRenameSelected,
            confirmDeleteSelected: confirmDeleteSelected
        )
    }

    private var shortcutBar: some View {
        ServerPropertiesShortcutBar()
    }
}

private enum ServerPropertiesMode {
    case visual
    case raw
}
