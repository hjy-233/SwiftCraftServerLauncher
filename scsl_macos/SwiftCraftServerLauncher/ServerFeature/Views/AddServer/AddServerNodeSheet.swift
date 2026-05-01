import SwiftUI

struct AddServerNodeSheet: View {
    @Environment(\.dismiss)
    private var dismiss
    @EnvironmentObject var serverNodeRepository: ServerNodeRepository

    @State private var name: String = ""
    @State private var host: String = ""
    @State private var port: String = "22"
    @State private var username: String = "root"
    @State private var remoteRootPath: String = "/opt/minecraft"
    @State private var password: String = ""
    @State private var isTesting: Bool = false
    @State private var testOutput: String = ""

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            Int(port) != nil &&
            !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        CommonSheetView(
            header: {
                HStack {
                    Text("node.add.title".localized())
                        .font(.headline)
                    Spacer()
                }
            },
            body: {
                VStack(alignment: .leading, spacing: 12) {
                    Text("node.add.unavailable_hint".localized())
                        .font(.caption)
                        .foregroundColor(.orange)

                    TextField("node.add.name".localized(), text: $name)
                        .textFieldStyle(.roundedBorder)
                    TextField("node.add.host".localized(), text: $host)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: host) { _, newValue in
                            applyHostPortAutofill(from: newValue)
                        }
                    TextField("node.add.port".localized(), text: $port)
                        .textFieldStyle(.roundedBorder)
                    TextField("node.add.username".localized(), text: $username)
                        .textFieldStyle(.roundedBorder)
                    SecureField("node.add.password".localized(), text: $password)
                        .textFieldStyle(.roundedBorder)
                    TextField("node.add.remote_root".localized(), text: $remoteRootPath)
                        .textFieldStyle(.roundedBorder)

                    if !testOutput.isEmpty {
                        Text(testOutput)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(4)
                    }
                }
            },
            footer: {
                HStack {
                    Button(isTesting ? "node.add.testing".localized() : "node.add.test".localized()) {
                        Task { await testConnection() }
                    }
                    .disabled(!isValid || password.isEmpty || isTesting)

                    Spacer()
                    Button("common.cancel".localized()) {
                        dismiss()
                    }
                    Button("common.save".localized()) {
                        saveNode()
                    }
                    .disabled(!isValid || password.isEmpty || isTesting)
                    .keyboardShortcut(.defaultAction)
                }
            }
        )
        .frame(width: 460)
        .onAppear {
            if name.isEmpty {
                name = "\("node.add.default_name_prefix".localized())\(serverNodeRepository.nodes.count)"
            }
        }
    }

    private func saveNode() {
        guard !testOutput.isEmpty else { return }
        let node = ServerNode(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: Int(port) ?? 22,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            remoteRootPath: remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines),
            isLocal: false
        )
        serverNodeRepository.addNode(node)
        savePassword(password, nodeId: node.id)
        dismiss()
    }

    private func testConnection() async {
        isTesting = true
        defer { isTesting = false }
        let node = ServerNode(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: Int(port) ?? 22,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            remoteRootPath: remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines),
            isLocal: false
        )
        do {
            let result = try await SSHNodeService.testConnectionAndPrepareDirectories(
                node: node,
                password: password
            )
            testOutput = "\("node.add.test_success".localized())\(result.output.replacingOccurrences(of: "\n", with: " "))"
        } catch {
            testOutput = "\("node.add.test_failed".localized())\(error.localizedDescription)"
        }
    }

    private func savePassword(_ password: String, nodeId: String) {
        let storageURL = AppPaths.dataDirectory.appendingPathComponent("server_node_passwords.json")
        var data: [String: String] = [:]
        if let existing = try? Data(contentsOf: storageURL),
           let decoded = try? JSONDecoder().decode([String: String].self, from: existing) {
            data = decoded
        }
        data[nodeId] = password
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: storageURL, options: .atomic)
        }
    }

    private func applyHostPortAutofill(from input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.hasPrefix("["),
           let rightBracket = trimmed.firstIndex(of: "]"),
           trimmed.index(after: rightBracket) < trimmed.endIndex,
           trimmed[trimmed.index(after: rightBracket)] == ":" {
            let hostPart = String(trimmed[trimmed.startIndex...rightBracket])
            let portPart = String(trimmed[trimmed.index(rightBracket, offsetBy: 2)...])
            if Int(portPart) != nil {
                if host != hostPart {
                    host = hostPart
                }
                if port != portPart {
                    port = portPart
                }
            }
            return
        }

        guard let colonIndex = trimmed.lastIndex(of: ":") else { return }
        let hostPart = String(trimmed[..<colonIndex])
        let portPart = String(trimmed[trimmed.index(after: colonIndex)...])
        guard !hostPart.isEmpty, Int(portPart) != nil else { return }
        if host != hostPart {
            host = hostPart
        }
        if port != portPart {
            port = portPart
        }
    }
}
