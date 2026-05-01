import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ServerCreationView: View {
    @StateObject private var viewModel: ServerCreationViewModel
    @StateObject private var generalSettings = GeneralSettingsManager.shared
    @StateObject private var mirrorSettings = MirrorSourceSettingsManager.shared
    @EnvironmentObject var serverRepository: ServerRepository
    @Environment(\.dismiss)
    private var dismiss

    private let triggerConfirm: Binding<Bool>
    private let triggerCancel: Binding<Bool>

    @State private var showJarPicker = false
    @State private var isJarDropTargeted = false
    @State private var isIconDropTargeted = false
    @State private var showFastMirrorPicker = false

    init(
        isDownloading: Binding<Bool>,
        isFormValid: Binding<Bool>,
        triggerConfirm: Binding<Bool>,
        triggerCancel: Binding<Bool>,
        selectedNode: ServerNode = .local,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        self.triggerConfirm = triggerConfirm
        self.triggerCancel = triggerCancel
        let configuration = GameFormConfiguration(
            isDownloading: isDownloading,
            isFormValid: isFormValid,
            triggerConfirm: triggerConfirm,
            triggerCancel: triggerCancel,
            onCancel: onCancel,
            onConfirm: onConfirm
        )
        self._viewModel = StateObject(
            wrappedValue: ServerCreationViewModel(
                configuration: configuration,
                selectedNode: selectedNode
            )
        )
    }

    var body: some View {
        formContentWithHandlers
            .fileImporter(
                isPresented: $showJarPicker,
                allowedContentTypes: [UTType(filenameExtension: "jar") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    viewModel.customJarURL = urls.first
                case .failure:
                    viewModel.customJarURL = nil
                }
            }
    }

    private var formContentWithHandlers: some View {
        formContentView
            .onAppear {
                viewModel.setup(serverRepository: serverRepository)
            }
            .onChange(of: viewModel.selectedServerType) { oldValue, newValue in
                if oldValue != newValue {
                    viewModel.handleServerTypeChange(newValue)
                    viewModel.updateParentState()
                }
            }
            .onChange(of: viewModel.selectedMirrorSource) { oldValue, newValue in
                if oldValue != newValue {
                    viewModel.handleMirrorSourceChange(newValue)
                    viewModel.updateParentState()
                }
            }
            .onChange(of: viewModel.selectedFastMirrorCoreName) { _, _ in
                viewModel.updateParentState()
            }
            .onChange(of: viewModel.selectedPolarsCoreTypeId) { _, _ in
                viewModel.updateParentState()
            }
            .onChange(of: viewModel.selectedPolarsCoreItemName) { _, _ in
                viewModel.updateParentState()
            }
            .onChange(of: viewModel.selectedMirrorDownloadURL) { _, _ in
                viewModel.updateParentState()
            }
            .onChange(of: viewModel.selectedMirrorFileName) { _, _ in
                viewModel.updateParentState()
            }
            .onChange(of: viewModel.selectedGameVersion) { oldValue, newValue in
                if oldValue != newValue {
                    viewModel.handleGameVersionChange(newValue)
                    viewModel.updateParentState()
                }
            }
            .onChange(of: viewModel.selectedLoaderVersion) { oldValue, newValue in
                if oldValue != newValue {
                    viewModel.updateParentState()
                }
            }
            .onChange(of: viewModel.serverNameValidator.serverName) { oldValue, newValue in
                if oldValue != newValue {
                    viewModel.updateParentState()
                }
            }
            .onChange(of: viewModel.serverNameValidator.isServerNameDuplicate) { oldValue, newValue in
                if oldValue != newValue {
                    viewModel.updateParentState()
                }
            }
            .onChange(of: viewModel.serverSetupService.downloadState.isDownloading) { oldValue, newValue in
                if oldValue != newValue {
                    viewModel.updateParentState()
                }
            }
            .onChange(of: viewModel.customJarURL) { _, _ in
                viewModel.updateParentState()
            }
            .onChange(of: triggerConfirm.wrappedValue) { _, newValue in
                if newValue {
                    if generalSettings.autoAcceptServerEULA {
                        viewModel.hasAcceptedEula = true
                        viewModel.handleConfirm()
                    } else {
                        let (decision, dontAskAgain) = presentEULAAlert()
                        switch decision {
                        case .accept:
                            viewModel.hasAcceptedEula = true
                            if dontAskAgain {
                                generalSettings.autoAcceptServerEULA = true
                            }
                            viewModel.handleConfirm()
                        case .decline:
                            viewModel.hasAcceptedEula = false
                            viewModel.handleConfirm()
                        case .cancel:
                            break
                        }
                    }
                    triggerConfirm.wrappedValue = false
                }
            }
            .onChange(of: triggerCancel.wrappedValue) { _, newValue in
                if newValue {
                    viewModel.handleCancel()
                    triggerCancel.wrappedValue = false
                }
            }
    }

    private enum EULAAlertDecision {
        case accept
        case decline
        case cancel
    }

    private final class EULAAlertHelpDelegate: NSObject, NSAlertDelegate {
        func alertShowHelp(_ alert: NSAlert) -> Bool {
            guard let url = URL(string: "https://aka.ms/MinecraftEULA") else { return false }
            NSWorkspace.shared.open(url)
            return true
        }
    }

    private func presentEULAAlert() -> (decision: EULAAlertDecision, dontAskAgain: Bool) {
        let alert = NSAlert()
        alert.messageText = "server.form.eula.confirm.title".localized()
        alert.informativeText = "server.form.eula.confirm.message".localized()
        alert.alertStyle = .warning
        alert.addButton(withTitle: "common.yes".localized())
        alert.addButton(withTitle: "common.no".localized())
        alert.addButton(withTitle: "common.cancel".localized())
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "server.form.eula.dont_ask_again".localized()
        let delegate = EULAAlertHelpDelegate()
        alert.delegate = delegate
        alert.showsHelp = true

        let response = alert.runModal()
        let dontAskAgain = alert.suppressionButton?.state == .on
        switch response {
        case .alertFirstButtonReturn:
            return (.accept, dontAskAgain)
        case .alertSecondButtonReturn:
            return (.decline, false)
        default:
            return (.cancel, false)
        }
    }

    private var formContentView: some View {
        VStack {
            FormSection {
                HStack(alignment: .top, spacing: 16) {
                    serverIconPicker
                    VStack(spacing: 10) {
                        mirrorSourcePicker
                        if viewModel.selectedMirrorSource == .official {
                            serverTypePicker
                            if viewModel.selectedServerType != .custom {
                                versionPicker
                            }
                            if viewModel.selectedServerType == .fabric || viewModel.selectedServerType == .forge {
                                loaderVersionPicker
                            }
                            if viewModel.selectedServerType == .custom {
                                customJarPicker
                            }
                        } else {
                            mirrorCorePicker
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }

            FormSection {
                ServerNameInputView(
                    serverName: Binding(
                        get: { viewModel.serverNameValidator.serverName },
                        set: { viewModel.serverNameValidator.serverName = $0 }
                    ),
                    isServerNameDuplicate: Binding(
                        get: { viewModel.serverNameValidator.isServerNameDuplicate },
                        set: { viewModel.serverNameValidator.isServerNameDuplicate = $0 }
                    ),
                    onNameChange: {
                        viewModel.updateParentState()
                    },
                    isDisabled: viewModel.serverSetupService.downloadState.isDownloading,
                    serverSetupService: viewModel.serverSetupService
                )
            }
        }
    }

    private var serverTypePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("server.form.type".localized())
                .font(.subheadline)
                .foregroundColor(.primary)
            Picker("", selection: $viewModel.selectedServerType) {
                ForEach(ServerType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .labelsHidden()
            .pickerStyle(MenuPickerStyle())
        }
    }

    private var mirrorSourcePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("server.form.mirror.source".localized())
                .font(.subheadline)
                .foregroundColor(.primary)
            mirrorSourceTabs
        }
        .onAppear {
            syncSelectedMirrorOption()
        }
        .onChange(of: mirrorSettings.sources) { _, _ in
            syncSelectedMirrorOption()
        }
    }

    private var mirrorSourceTabs: some View {
        let options = mirrorSourceOptions
        if options.count > 4 {
            return AnyView(
                Picker("", selection: mirrorSourceSelectionBinding) {
                    ForEach(options) { option in
                        Text(option.displayName).tag(option.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(MenuPickerStyle())
            )
        }

        return AnyView(
            Picker("", selection: mirrorSourceSelectionBinding) {
                ForEach(options) { option in
                    Text(option.displayName).tag(option.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        )
    }

    private var mirrorCorePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.selectedMirrorDisplayName)
                .font(.subheadline)
                .foregroundColor(.primary)
            ZStack {
                TextField("", text: .constant(""))
                    .textFieldStyle(.roundedBorder)
                    .allowsHitTesting(false)
                    .focusable(false)
                HStack {
                    Text(mirrorSummaryText)
                        .foregroundColor(
                            mirrorSummaryTextIsPlaceholder
                                ? .secondary
                                : .primary
                        )
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .onTapGesture {
                showFastMirrorPicker.toggle()
            }
            .popover(isPresented: $showFastMirrorPicker, arrowEdge: .trailing) {
                mirrorSelectionColumns
            }
        }
    }

    private var mirrorSelectionColumns: some View {
        switch viewModel.selectedMirrorSource {
        case .fastMirror:
            return AnyView(fastMirrorSelectionColumns)
        case .custom:
            return AnyView(fastMirrorSelectionColumns)
        case .polars:
            return AnyView(polarsSelectionColumns)
        case .official:
            return AnyView(EmptyView())
        }
    }

    private var fastMirrorSelectionColumns: some View {
        HStack(alignment: .top, spacing: 12) {
            mirrorColumn(
                title: "server.form.mirror.core".localized(),
                items: viewModel.fastMirrorCores.map(\.name),
                selection: Binding<String?>(
                    get: { viewModel.selectedFastMirrorCoreName.isEmpty ? nil : viewModel.selectedFastMirrorCoreName },
                    set: { newValue in
                        if let newValue {
                            viewModel.handleFastMirrorCoreChange(newValue)
                        }
                    }
                )
            )

            mirrorColumn(
                title: "server.form.mirror.version".localized(),
                items: viewModel.availableVersions,
                selection: Binding<String?>(
                    get: { viewModel.selectedGameVersion.isEmpty ? nil : viewModel.selectedGameVersion },
                    set: { newValue in
                        viewModel.selectedGameVersion = newValue ?? ""
                    }
                )
            )

            mirrorColumn(
                title: "server.form.mirror.core_version".localized(),
                items: viewModel.availableLoaderVersions,
                selection: Binding<String?>(
                    get: { viewModel.selectedLoaderVersion.isEmpty ? nil : viewModel.selectedLoaderVersion },
                    set: { newValue in
                        viewModel.handleMirrorCoreVersionChange(newValue ?? "")
                    }
                )
            )
        }
        .padding(12)
        .frame(minWidth: 540)
    }

    private var polarsSelectionColumns: some View {
        HStack(alignment: .top, spacing: 12) {
            mirrorColumn(
                title: "server.form.mirror.core".localized(),
                items: viewModel.polarsCoreTypes.map { $0.name },
                selection: Binding<String?>(
                    get: {
                        guard let id = viewModel.selectedPolarsCoreTypeId else { return nil }
                        return viewModel.polarsCoreTypes.first { $0.id == id }?.name
                    },
                    set: { newValue in
                        guard let newValue,
                              let type = viewModel.polarsCoreTypes.first(where: { $0.name == newValue }) else {
                            return
                        }
                        viewModel.handlePolarsCoreTypeChange(type.id)
                    }
                )
            )
            mirrorColumn(
                title: "server.form.mirror.core_version".localized(),
                items: viewModel.polarsCoreItems.map(\.name),
                selection: Binding<String?>(
                    get: { viewModel.selectedPolarsCoreItemName.isEmpty ? nil : viewModel.selectedPolarsCoreItemName },
                    set: { newValue in
                        guard let newValue,
                              let item = viewModel.polarsCoreItems.first(where: { $0.name == newValue }) else {
                            return
                        }
                        viewModel.handlePolarsCoreItemChange(item)
                    }
                )
            )
        }
        .padding(12)
        .frame(minWidth: 420)
    }

    private var mirrorSummaryText: String {
        switch viewModel.selectedMirrorSource {
        case .fastMirror:
            let core = viewModel.selectedFastMirrorCoreName
            let gameVersion = viewModel.selectedGameVersion
            let coreVersion = viewModel.selectedLoaderVersion
            if core.isEmpty {
                return "server.form.mirror.fastmirror.placeholder".localized()
            }
            var parts = [core]
            if !gameVersion.isEmpty {
                parts.append(gameVersion)
            }
            if !coreVersion.isEmpty {
                parts.append(coreVersion)
            }
            return parts.joined(separator: " · ")
        case .custom:
            let core = viewModel.selectedFastMirrorCoreName
            let gameVersion = viewModel.selectedGameVersion
            let coreVersion = viewModel.selectedLoaderVersion
            if core.isEmpty {
                return "server.form.mirror.fastmirror.placeholder".localized()
            }
            var parts = [core]
            if !gameVersion.isEmpty {
                parts.append(gameVersion)
            }
            if !coreVersion.isEmpty {
                parts.append(coreVersion)
            }
            return parts.joined(separator: " · ")
        case .polars:
            let typeName = viewModel.polarsCoreTypes.first { $0.id == viewModel.selectedPolarsCoreTypeId }?.name ?? ""
            let itemName = viewModel.selectedPolarsCoreItemName
            if typeName.isEmpty {
                return "server.form.mirror.fastmirror.placeholder".localized()
            }
            if itemName.isEmpty {
                return typeName
            }
            return "\(typeName) · \(itemName)"
        case .official:
            return ""
        }
    }

    private var mirrorSummaryTextIsPlaceholder: Bool {
        switch viewModel.selectedMirrorSource {
        case .fastMirror:
            return viewModel.selectedFastMirrorCoreName.isEmpty
        case .custom:
            return viewModel.selectedFastMirrorCoreName.isEmpty
        case .polars:
            return viewModel.selectedPolarsCoreTypeId == nil
        case .official:
            return false
        }
    }

    private struct MirrorSourceOption: Identifiable, Hashable {
        let id: String
        let displayName: String
        let source: ServerMirrorSource
        let baseURL: String?
        let customJSON: String?
    }

    private var mirrorSourceOptions: [MirrorSourceOption] {
        var options: [MirrorSourceOption] = [
            MirrorSourceOption(
                id: ServerMirrorSource.official.id,
                displayName: ServerMirrorSource.official.displayName,
                source: .official,
                baseURL: nil,
                customJSON: nil
            ),
        ]
        let mirrorItems = mirrorSettings.enabledSources.map { source in
            MirrorSourceOption(
                id: "mirror-\(source.id.uuidString)",
                displayName: source.name,
                source: mirrorSourceKind(from: source.kind),
                baseURL: source.baseURL,
                customJSON: source.customJSON
            )
        }
        options.append(contentsOf: mirrorItems)
        return options
    }

    private func mirrorSourceKind(from kind: MirrorSourceKind) -> ServerMirrorSource {
        switch kind {
        case .fastMirror:
            return .fastMirror
        case .polars:
            return .polars
        case .custom:
            return .custom
        }
    }

    private var mirrorSourceSelectionBinding: Binding<String> {
        Binding(
            get: { viewModel.selectedMirrorSourceId },
            set: { newValue in
                guard let option = mirrorSourceOptions.first(where: { $0.id == newValue }) else { return }
                applyMirrorOption(option)
            }
        )
    }

    private func applyMirrorOption(_ option: MirrorSourceOption) {
        viewModel.applyMirrorSelection(
            sourceId: option.id,
            source: option.source,
            displayName: option.displayName,
            baseURL: option.baseURL,
            customJSON: option.customJSON
        )
    }

    private func syncSelectedMirrorOption() {
        guard let option = mirrorSourceOptions.first(where: { $0.id == viewModel.selectedMirrorSourceId }) else {
            if let first = mirrorSourceOptions.first {
                applyMirrorOption(first)
            }
            return
        }
        if option.displayName != viewModel.selectedMirrorDisplayName {
            applyMirrorOption(option)
        }
    }

    private func mirrorColumn(
        title: String,
        items: [String],
        selection: Binding<String?>
    ) -> some View {
        MirrorSelectionColumnView(title: title, items: items, selection: selection)
    }

    private var serverIconPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("server.form.icon".localized())
                .font(.subheadline)
                .foregroundColor(.primary)
            Button {
                chooseServerIcon()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isIconDropTargeted ? Color.accentColor : Color.secondary.opacity(0.5),
                            style: StrokeStyle(lineWidth: 1.5, dash: [8, 6])
                        )
                    if let image = selectedIconPreviewImage {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(2)
                    } else {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.green)
                                .background(Circle().fill(Color(NSColor.windowBackgroundColor)))
                        }
                    }
                    .padding(8)
                }
                .frame(width: 96, height: 96)
            }
            .buttonStyle(.plain)
            .onDrop(of: [.fileURL], isTargeted: $isIconDropTargeted) { providers in
                handleIconDrop(providers: providers)
            }
        }
    }

    private var selectedIconPreviewImage: NSImage? {
        guard let url = viewModel.selectedServerIconURL else { return nil }
        return NSImage(contentsOf: url)
    }

    private func chooseServerIcon() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.title = "server.form.icon".localized()
        if panel.runModal() == .OK {
            viewModel.selectedServerIconURL = panel.url
        }
    }

    private func handleIconDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }
            Task { @MainActor in
                let fileType = UTType(filenameExtension: url.pathExtension)
                guard fileType?.conforms(to: .image) == true else {
                    return
                }
                viewModel.selectedServerIconURL = url
            }
        }
        return true
    }

    private var versionPicker: some View {
        CustomVersionPicker(
            selected: $viewModel.selectedGameVersion,
            availableVersions: viewModel.availableVersions,
            time: $viewModel.versionTime
        ) { version in
            await ModrinthService.queryVersionTime(from: version)
        }
    }

    private var loaderVersionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("server.form.loader.version".localized())
                .font(.subheadline)
                .foregroundColor(.primary)
            Picker("", selection: $viewModel.selectedLoaderVersion) {
                ForEach(viewModel.availableLoaderVersions, id: \.self) { version in
                    Text(version).tag(version)
                }
            }
            .labelsHidden()
            .pickerStyle(MenuPickerStyle())
            .disabled(viewModel.availableLoaderVersions.isEmpty)
        }
    }

    private var customJarPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("server.form.custom.jar".localized())
                .font(.subheadline)
                .foregroundColor(.primary)
            HStack(spacing: 8) {
                Button {
                    chooseCustomJar()
                } label: {
                    Text("server.form.custom.jar.select".localized())
                }
                if let url = viewModel.customJarURL {
                    Text(url.lastPathComponent)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text("server.form.custom.jar.empty".localized())
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isJarDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                        style: StrokeStyle(lineWidth: isJarDropTargeted ? 2 : 1, dash: [6, 4])
                    )
            )
            .onDrop(of: [UTType.fileURL], isTargeted: $isJarDropTargeted) { providers in
                handleJarDrop(providers: providers)
            }
        }
    }

    private func chooseCustomJar() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "jar") ?? .data]
        panel.title = "server.form.custom.jar.select".localized()
        if panel.runModal() == .OK, let url = panel.url {
            guard url.pathExtension.lowercased() == "jar" else {
                viewModel.customJarURL = nil
                GlobalErrorHandler.shared.handle(
                    GlobalError.validation(
                        chineseMessage: "请选择 .jar 文件",
                        i18nKey: "error.validation.invalid_file_type",
                        level: .notification
                    )
                )
                return
            }
            viewModel.customJarURL = url
        }
    }

    private func handleJarDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }
            Task { @MainActor in
                guard url.pathExtension.lowercased() == "jar" else {
                    GlobalErrorHandler.shared.handle(
                        GlobalError.validation(
                            chineseMessage: "请选择 .jar 文件",
                            i18nKey: "error.validation.invalid_file_type",
                            level: .notification
                        )
                    )
                    return
                }
                viewModel.customJarURL = url
            }
        }
        return true
    }
}
