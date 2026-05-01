import SwiftUI

/// Runtime / launch settings. Uses standard macOS form rhythm: light labels, no double borders,
/// grouped sections — avoids “boxed text on boxed field” stacking that reads as cheap UI.
struct ServerRuntimeSettingsView: View {
    let server: ServerInstance
    var showPageHeader: Bool = true
    var externalAdvancedEditorRequest: Binding<Bool>?
    @EnvironmentObject var serverRepository: ServerRepository

    @State private var javaPath: String = "java"
    @State private var availableJavaPaths: [String] = []
    @State private var jvmArguments: String = ""
    @State private var xmsText: String = ""
    @State private var xmxText: String = ""
    @State private var customLaunchCommand: String = ""
    @State private var showAdvancedEditor = false
    @State private var advancedLaunchCommand: String = ""
    @State private var selectedJVMPreset: String = "custom"
    @State private var isDirty = false
    @State private var autosaveTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if showPageHeader {
                    pageHeader
                        .padding(.bottom, 20)
                }

                settingsSection {
                    editableRow(
                        label: "server.runtime.java_path".localized(),
                        hint: "server.runtime.jvm.hint".localized()
                    ) {
                        Picker("server.runtime.java_path".localized(), selection: $javaPath) {
                            ForEach(availableJavaPaths, id: \.self) { path in
                                Text(path).tag(path)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .onChange(of: javaPath) { _, _ in
                            markDirtyFromFields()
                        }
                    }
                    editableRow(
                        label: "server.runtime.jvm".localized(),
                        hint: "server.runtime.jvm.hint".localized()
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("", selection: $selectedJVMPreset) {
                                Text("Default").tag("default")
                                Text("G1GC").tag("g1gc")
                                Text("Aikar").tag("aikar")
                                Text("ZGC").tag("zgc")
                                Text("Custom").tag("custom")
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .onChange(of: selectedJVMPreset) { _, newValue in
                                applyJVMPreset(newValue)
                            }

                            TextField("", text: $jvmArguments, axis: .vertical)
                                .lineLimit(2...4)
                                .onChange(of: jvmArguments) { _, _ in
                                    updateJVMPresetSelection()
                                    markDirtyFromFields()
                                }
                        }
                    }
                }

                settingsSection(title: "server.runtime.section.memory".localized()) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("server.runtime.memory.xms".localized())
                                .font(.callout.weight(.medium))
                            Text("server.runtime.memory.hint".localized())
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            TextField("0", text: $xmsText)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: xmsText) { _, newValue in
                                    xmsText = filteredDigits(from: newValue)
                                    markDirtyFromFields()
                                }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("server.runtime.memory.xmx".localized())
                                .font(.callout.weight(.medium))
                            Text("server.runtime.memory.hint".localized())
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            TextField("0", text: $xmxText)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: xmxText) { _, newValue in
                                    xmxText = filteredDigits(from: newValue)
                                    markDirtyFromFields()
                                }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(showPageHeader ? 24 : 0)
        }
        .sheet(isPresented: $showAdvancedEditor) {
            CommonSheetView {
                Text("server.launch.title".localized())
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } body: {
                TextEditor(text: $advancedLaunchCommand)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 760, height: 360)
            } footer: {
                HStack {
                    Button("common.cancel".localized()) {
                        showAdvancedEditor = false
                    }
                    Spacer()
                    Button("common.save".localized()) {
                        applyAdvancedLaunchCommand()
                        showAdvancedEditor = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .onAppear {
            loadFromServer()
        }
        .onChange(of: server.id) { _, _ in
            loadFromServer()
        }
        .onChange(of: externalAdvancedEditorRequest?.wrappedValue ?? false) { _, requested in
            guard requested else { return }
            advancedLaunchCommand = customLaunchCommand
            showAdvancedEditor = true
            externalAdvancedEditorRequest?.wrappedValue = false
        }
        .onDisappear {
            autosaveTask?.cancel()
            saveIfNeeded()
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("server.runtime.title".localized())
                .font(.title2.weight(.semibold))
            Text("server.runtime.page.subtitle".localized())
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func settingsSection<Content: View>(
        title: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .padding(.bottom, 28)
    }

    private func editableRow<Content: View>(
        label: String,
        hint: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.callout.weight(.medium))
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
                .textFieldStyle(.roundedBorder)
        }
    }

    private func loadFromServer() {
        javaPath = server.javaPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "java" : server.javaPath
        jvmArguments = server.jvmArguments
        xmsText = server.xms > 0 ? String(server.xms) : ""
        xmxText = server.xmx > 0 ? String(server.xmx) : ""
        availableJavaPaths = scanLocalJavaExecutables(current: javaPath)
        customLaunchCommand = server.launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        if customLaunchCommand.isEmpty {
            customLaunchCommand = buildLaunchCommandFromFields()
        } else {
            applyCommandToFields(customLaunchCommand)
        }
        updateJVMPresetSelection()
        isDirty = false
    }

    private func markDirtyFromFields() {
        customLaunchCommand = buildLaunchCommandFromFields()
        markDirty()
    }

    private func markDirty() {
        isDirty = true
        scheduleAutosave()
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        guard isDirty else { return }
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                saveIfNeeded()
            }
        }
    }

    private func saveIfNeeded() {
        guard isDirty else { return }
        var updated = server
        updated.javaPath = javaPath.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.launchCommand = customLaunchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.jvmArguments = jvmArguments.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.xms = Int(xmsText) ?? 0
        updated.xmx = Int(xmxText) ?? 0
        _ = serverRepository.updateServerSilently(updated)
        isDirty = false
    }

    private func buildLaunchCommandFromFields() -> String {
        let resolvedJavaPath = javaPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "java" : javaPath.trimmingCharacters(in: .whitespacesAndNewlines)
        var args: [String] = []
        if let xms = Int(xmsText), xms > 0 {
            args.append("-Xms\(xms)M")
        }
        if let xmx = Int(xmxText), xmx > 0 {
            args.append("-Xmx\(xmx)M")
        }
        let trimmedJvm = jvmArguments.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedJvm.isEmpty {
            args.append(contentsOf: splitArgs(trimmedJvm))
        }
        args.append(contentsOf: ["-jar", server.serverJar, "nogui"])
        return ([resolvedJavaPath] + args).joined(separator: " ")
    }

    private func applyAdvancedLaunchCommand() {
        let trimmed = advancedLaunchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        customLaunchCommand = trimmed
        applyCommandToFields(trimmed)
        updateJVMPresetSelection()
        markDirty()
    }

    private func applyCommandToFields(_ command: String) {
        let tokens = splitArgs(command)
        guard !tokens.isEmpty else { return }

        var inferredJavaPath = javaPath
        var inferredJvm: [String] = []
        var inferredXms: Int?
        var inferredXmx: Int?

        var index = 0
        if let first = tokens.first, !first.hasPrefix("-"), first != "java" {
            inferredJavaPath = first
            index = 1
        } else if tokens.first == "java" {
            inferredJavaPath = "java"
            index = 1
        }
        while index < tokens.count {
            let token = tokens[index]
            if token == "-jar" {
                break
            }
            if let parsedXms = parseMemory(token, prefix: "-Xms") {
                inferredXms = parsedXms
            } else if let parsedXmx = parseMemory(token, prefix: "-Xmx") {
                inferredXmx = parsedXmx
            } else {
                inferredJvm.append(token)
            }
            index += 1
        }

        javaPath = inferredJavaPath
        if !availableJavaPaths.contains(javaPath) {
            availableJavaPaths = scanLocalJavaExecutables(current: javaPath)
        }
        jvmArguments = inferredJvm.joined(separator: " ")
        xmsText = inferredXms.map(String.init) ?? ""
        xmxText = inferredXmx.map(String.init) ?? ""
        updateJVMPresetSelection()
    }

    private func applyJVMPreset(_ preset: String) {
        guard preset != "custom" else { return }
        switch preset {
        case "default":
            jvmArguments = ""
        case "g1gc":
            jvmArguments = "-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200"
        case "aikar":
            jvmArguments = "-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:+UnlockExperimentalVMOptions -XX:G1NewSizePercent=20 -XX:G1ReservePercent=20 -XX:MaxGCPauseMillis=200"
        case "zgc":
            jvmArguments = "-XX:+UseZGC -XX:+ZGenerational"
        default:
            break
        }
        markDirtyFromFields()
    }

    private func updateJVMPresetSelection() {
        let trimmed = jvmArguments.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed {
        case "":
            selectedJVMPreset = "default"
        case "-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200":
            selectedJVMPreset = "g1gc"
        case "-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:+UnlockExperimentalVMOptions -XX:G1NewSizePercent=20 -XX:G1ReservePercent=20 -XX:MaxGCPauseMillis=200":
            selectedJVMPreset = "aikar"
        case "-XX:+UseZGC -XX:+ZGenerational":
            selectedJVMPreset = "zgc"
        default:
            selectedJVMPreset = "custom"
        }
    }

    private func parseMemory(_ token: String, prefix: String) -> Int? {
        guard token.hasPrefix(prefix) else { return nil }
        let raw = token.replacingOccurrences(of: prefix, with: "")
        if raw.hasSuffix("G"), let value = Int(raw.dropLast()) {
            return value * 1024
        }
        if raw.hasSuffix("M"), let value = Int(raw.dropLast()) {
            return value
        }
        return Int(raw)
    }

    private func splitArgs(_ input: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var quoteChar: Character = "\""

        for char in input {
            if char == "\"" || char == "'" {
                if inQuotes && char == quoteChar {
                    inQuotes = false
                } else if !inQuotes {
                    inQuotes = true
                    quoteChar = char
                } else {
                    current.append(char)
                }
                continue
            }

            if char == " " && !inQuotes {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    private func scanLocalJavaExecutables(current: String) -> [String] {
        var candidates: Set<String> = ["java"]

        let defaultLocations = [
            "/usr/bin/java",
            "/opt/homebrew/bin/java",
            "/usr/local/bin/java",
        ]
        for path in defaultLocations where FileManager.default.isExecutableFile(atPath: path) {
            candidates.insert(path)
        }

        let vmRoot = URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines")
        if let vmDirs = try? FileManager.default.contentsOfDirectory(
            at: vmRoot,
            includingPropertiesForKeys: nil
        ) {
            for vm in vmDirs {
                let java = vm.appendingPathComponent("Contents/Home/bin/java").path
                if FileManager.default.isExecutableFile(atPath: java) {
                    candidates.insert(java)
                }
            }
        }

        let sdkmanRoot = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".sdkman/candidates/java")
        if let sdkmanDirs = try? FileManager.default.contentsOfDirectory(
            at: sdkmanRoot,
            includingPropertiesForKeys: nil
        ) {
            for sdk in sdkmanDirs {
                let java = sdk.appendingPathComponent("bin/java").path
                if FileManager.default.isExecutableFile(atPath: java) {
                    candidates.insert(java)
                }
            }
        }

        let trimmedCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCurrent.isEmpty {
            candidates.insert(trimmedCurrent)
        }
        return candidates.sorted()
    }

    private func filteredDigits(from value: String) -> String {
        value.filter(\.isNumber)
    }
}
