import SwiftUI

public struct MirrorSourceSettingsView: View {
    @StateObject private var settings = MirrorSourceSettingsManager.shared
    @State private var selection: MirrorSourceConfig.ID?
    @State private var editorMode: EditorMode?
    @State private var isEditingJSON = false
    @State private var customConfigDraft = MirrorCustomAPIConfig.defaultConfig
    @State private var customJSONText = MirrorCustomAPIConfig.defaultJSON
    @State private var customJSONError: String = ""
    @State private var showPreview = false
    @State private var editorDraft = MirrorSourceConfig(
        name: "",
        kind: .fastMirror,
        baseURL: "https://",
        customJSON: nil,
        isEnabled: true,
        isBuiltIn: false
    )

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("settings.mirror.header".localized())
                .font(.headline)
            Text("settings.mirror.footer".localized())
                .font(.subheadline)
                .foregroundColor(.secondary)

            List(selection: $selection) {
                ForEach(settings.sources) { source in
                    mirrorRow(source: source)
                        .tag(source.id)
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            mirrorActionBar
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: Binding<Bool>(
            get: { editorMode != nil },
            set: { if !$0 { editorMode = nil } }
        )) {
            mirrorEditorSheet
        }
    }

    private var mirrorActionBar: some View {
        HStack(spacing: 0) {
            Button {
                beginAdd()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 22, height: 20)
            }
            .buttonStyle(.borderless)

            Divider()
                .frame(height: 18)

            Button {
                removeSelection()
            } label: {
                Image(systemName: "minus")
                    .frame(width: 22, height: 20)
            }
            .buttonStyle(.borderless)
            .disabled(!canRemoveSelection)

            Divider()
                .frame(height: 18)

            Button {
                setSelectionEnabled(true)
            } label: {
                Image(systemName: "checkmark.circle")
                    .frame(width: 22, height: 20)
            }
            .buttonStyle(.borderless)
            .disabled(selection == nil || isSelectionEnabled)

            Divider()
                .frame(height: 18)

            Button {
                setSelectionEnabled(false)
            } label: {
                Image(systemName: "xmark.circle")
                    .frame(width: 22, height: 20)
            }
            .buttonStyle(.borderless)
            .disabled(selection == nil || !isSelectionEnabled)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func mirrorRow(source: MirrorSourceConfig) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(.body)
                Text(source.kind.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(source.baseURL)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .opacity(source.isEnabled ? 1 : 0.5)
        .contentShape(Rectangle())
        .onTapGesture {
            selection = source.id
        }
        .highPriorityGesture(
            TapGesture(count: 2).onEnded {
                beginEdit(source)
            }
        )
    }

    private var mirrorEditorSheet: some View {
        CommonSheetView {
            Text(editorMode == .add ? "settings.mirror.add".localized() : "settings.mirror.edit".localized())
                .font(.headline)
        } body: {
            VStack(alignment: .leading, spacing: 12) {
                TextField(
                    "settings.mirror.name.placeholder".localized(),
                    text: $editorDraft.name
                )
                Picker("", selection: $editorDraft.kind) {
                    ForEach(MirrorSourceKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .labelsHidden()
                .pickerStyle(MenuPickerStyle())

                TextField(
                    "settings.mirror.url.placeholder".localized(),
                    text: $editorDraft.baseURL
                )

                Toggle("settings.mirror.enabled".localized(), isOn: $editorDraft.isEnabled)
                customEditorSection
            }
            .onChange(of: editorDraft.kind) { _, newValue in
                if newValue == .custom {
                    syncCustomDraft(from: editorDraft)
                }
            }
            .onChange(of: isEditingJSON) { _, newValue in
                if newValue {
                    customJSONText = resolvedCustomJSON()
                } else {
                    syncCustomDraftFromJSON()
                }
            }
            .onChange(of: customConfigDraft) { _, _ in
                guard editorDraft.kind == .custom, !isEditingJSON else { return }
                customJSONText = resolvedCustomJSON()
            }
            .onChange(of: customJSONText) { _, _ in
                guard editorDraft.kind == .custom, isEditingJSON else { return }
                syncCustomDraftFromJSON()
            }
        } footer: {
            HStack {
                Spacer()
                Button("common.cancel".localized()) {
                    editorMode = nil
                }
                Button("common.save".localized()) {
                    if validateCustomJSON() {
                        saveDraft()
                        editorMode = nil
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var customEditorSection: some View {
        Group {
            if editorDraft.kind == .custom {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Toggle(
                            "settings.mirror.custom.edit_json".localized(),
                            isOn: $isEditingJSON
                        )
                        .toggleStyle(.checkbox)
                        Spacer()
                        Button("settings.mirror.custom.preview".localized()) {
                            showPreview.toggle()
                        }
                        .buttonStyle(.bordered)
                    }

                    Text("settings.mirror.custom.placeholders".localized())
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if isEditingJSON {
                        TextEditor(text: $customJSONText)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 180)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    } else {
                        customConfigForm
                    }

                    if !customJSONError.isEmpty {
                        Text(customJSONError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    if showPreview {
                        EmptyView()
                    }
                }
                .padding(.top, 4)
            }
        }
        .popover(isPresented: $showPreview, arrowEdge: .trailing) {
            mirrorPreviewView
                .padding(12)
        }
    }

    private var customConfigForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("settings.mirror.custom.path.cores".localized()) {
                TextField("", text: $customConfigDraft.coreListPath)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("settings.mirror.custom.path.core_detail".localized()) {
                TextField("", text: $customConfigDraft.coreDetailPath)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("settings.mirror.custom.path.builds".localized()) {
                TextField("", text: $customConfigDraft.coreBuildsPath)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("settings.mirror.custom.path.build_detail".localized()) {
                TextField("", text: $customConfigDraft.coreBuildDetailPath)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("settings.mirror.custom.unwrap_data".localized()) {
                Toggle("", isOn: $customConfigDraft.unwrapData)
                    .labelsHidden()
            }

            Divider()

            LabeledContent("settings.mirror.custom.key.cores".localized()) {
                TextField("", text: $customConfigDraft.coresKeyPath)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("settings.mirror.custom.key.core_name".localized()) {
                TextField("", text: $customConfigDraft.coreNameKey)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("settings.mirror.custom.key.versions".localized()) {
                TextField("", text: $customConfigDraft.versionsKeyPath)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("settings.mirror.custom.key.builds".localized()) {
                TextField("", text: $customConfigDraft.buildsKeyPath)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("settings.mirror.custom.key.build_version".localized()) {
                TextField("", text: $customConfigDraft.buildVersionKey)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("settings.mirror.custom.key.download_url".localized()) {
                TextField("", text: $customConfigDraft.buildDownloadURLKey)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("settings.mirror.custom.key.filename".localized()) {
                TextField("", text: $customConfigDraft.buildFileNameKey)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("settings.mirror.custom.key.sha1".localized()) {
                TextField("", text: $customConfigDraft.buildSha1Key)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var canRemoveSelection: Bool {
        guard let selection,
              let source = settings.sources.first(where: { $0.id == selection }) else {
            return false
        }
        return !source.isBuiltIn
    }

    private var isSelectionEnabled: Bool {
        guard let selection,
              let source = settings.sources.first(where: { $0.id == selection }) else {
            return false
        }
        return source.isEnabled
    }

    private func removeSelection() {
        guard let selection,
              let source = settings.sources.first(where: { $0.id == selection }),
              !source.isBuiltIn else { return }
        settings.removeSource(id: source.id)
        self.selection = nil
    }

    private func setSelectionEnabled(_ enabled: Bool) {
        guard let selection,
              let index = settings.sources.firstIndex(where: { $0.id == selection }) else {
            return
        }
        settings.sources[index].isEnabled = enabled
    }

    private func beginAdd() {
        editorDraft = MirrorSourceConfig(
            name: "settings.mirror.custom.default_name".localized(),
            kind: .custom,
            baseURL: "https://",
            customJSON: MirrorCustomAPIConfig.defaultJSON,
            isEnabled: true,
            isBuiltIn: false
        )
        isEditingJSON = false
        showPreview = false
        syncCustomDraft(from: editorDraft)
        editorMode = .add
    }

    private func beginEdit(_ source: MirrorSourceConfig) {
        guard !source.isBuiltIn else { return }
        editorDraft = source
        isEditingJSON = false
        showPreview = false
        syncCustomDraft(from: source)
        editorMode = .edit
    }

    private func saveDraft() {
        if editorDraft.kind == .custom {
            editorDraft.customJSON = resolvedCustomJSON()
        } else {
            editorDraft.customJSON = nil
        }
        switch editorMode {
        case .add:
            settings.sources.append(editorDraft)
        case .edit:
            if let index = settings.sources.firstIndex(where: { $0.id == editorDraft.id }) {
                settings.sources[index] = editorDraft
            }
        case .none:
            break
        }
    }

    private func syncCustomDraft(from source: MirrorSourceConfig) {
        let jsonText = source.customJSON ?? MirrorCustomAPIConfig.defaultJSON
        customJSONText = jsonText
        if let data = jsonText.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(MirrorCustomAPIConfig.self, from: data) {
            if decoded.baseURL.isEmpty, !source.baseURL.isEmpty {
                var updated = decoded
                updated.baseURL = source.baseURL
                customConfigDraft = updated
                customJSONText = encodeCustomConfig(updated)
            } else {
                customConfigDraft = decoded
                if !decoded.baseURL.isEmpty {
                    editorDraft.baseURL = decoded.baseURL
                }
            }
            customJSONError = ""
        } else {
            customConfigDraft = MirrorCustomAPIConfig.defaultConfig
            customJSONError = "settings.mirror.custom.invalid_json".localized()
        }
    }

    private func syncCustomDraftFromJSON() {
        guard let data = customJSONText.data(using: .utf8),
              var decoded = try? JSONDecoder().decode(MirrorCustomAPIConfig.self, from: data) else {
            customJSONError = "settings.mirror.custom.invalid_json".localized()
            return
        }
        if decoded.baseURL.isEmpty {
            decoded.baseURL = editorDraft.baseURL
            customJSONText = encodeCustomConfig(decoded)
        }
        customConfigDraft = decoded
        if !decoded.baseURL.isEmpty {
            editorDraft.baseURL = decoded.baseURL
        }
        customJSONError = ""
    }

    private func resolvedCustomJSON() -> String {
        if isEditingJSON {
            return customJSONText
        }
        customConfigDraft.baseURL = editorDraft.baseURL
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(customConfigDraft),
              let text = String(data: data, encoding: .utf8) else {
            return MirrorCustomAPIConfig.defaultJSON
        }
        return text
    }

    private func validateCustomJSON() -> Bool {
        guard editorDraft.kind == .custom else { return true }
        if isEditingJSON {
            guard let data = customJSONText.data(using: .utf8),
                  var decoded = try? JSONDecoder().decode(MirrorCustomAPIConfig.self, from: data) else {
                customJSONError = "settings.mirror.custom.invalid_json".localized()
                return false
            }
            if decoded.baseURL.isEmpty {
                decoded.baseURL = editorDraft.baseURL
                if decoded.baseURL.isEmpty {
                    customJSONError = "settings.mirror.custom.base_url_required".localized()
                    return false
                }
                customJSONText = encodeCustomConfig(decoded)
            }
        } else {
            customJSONText = resolvedCustomJSON()
        }
        customJSONError = ""
        return true
    }

    private func encodeCustomConfig(_ config: MirrorCustomAPIConfig) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config),
              let text = String(data: data, encoding: .utf8) else {
            return MirrorCustomAPIConfig.defaultJSON
        }
        return text
    }

    private var mirrorPreviewView: some View {
        MirrorPreviewView()
    }

    private enum EditorMode {
        case add
        case edit
    }
}

private struct MirrorPreviewView: View {
    @State private var selectedCore: String? = "Arclight"
    @State private var selectedGameVersion: String? = "1.21-neoforge"
    @State private var selectedCoreVersion: String? = "1.0.2-4f2d372"

    private let cores = ["Arclight", "BungeeCord", "CatServer", "Fabric", "Folia", "Forge", "Leaves"]
    private let versions = ["1.21-neoforge", "1.21-forge", "1.21-fabric", "1.21.1-neoforge", "1.21.1-forge", "1.21.1-fabric"]
    private let builds = ["1.0.2-4f2d372", "1.0.2-9c004d4", "1.0.2-2e9399c", "1.0.2-54317e7", "1.0.2-012d6d8", "1.0.2-6cd09d2"]

    var body: some View {
        HStack(spacing: 12) {
            MirrorSelectionColumnView(
                title: "server.form.mirror.core".localized(),
                items: cores,
                selection: $selectedCore
            )
            MirrorSelectionColumnView(
                title: "server.form.mirror.version".localized(),
                items: versions,
                selection: $selectedGameVersion
            )
            MirrorSelectionColumnView(
                title: "server.form.mirror.core_version".localized(),
                items: builds,
                selection: $selectedCoreVersion
            )
        }
        .padding(8)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

#Preview {
    MirrorSourceSettingsView()
}
