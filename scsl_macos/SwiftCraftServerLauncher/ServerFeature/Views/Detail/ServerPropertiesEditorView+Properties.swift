import SwiftUI

extension ServerPropertiesEditorView {
    var filteredKeys: [String] {
        let keys = properties.keys.sorted()
        let query = searchText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return keys }
        return keys.filter { key in
            let value = properties[key]?.lowercased() ?? ""
            let localized = localizedName(for: key).lowercased()
            return key.lowercased().contains(query) || localized.contains(query) || value.contains(query)
        }
    }

    func propertyRow(key: String) -> some View {
        let value = properties[key] ?? ""
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Text(key)
                    .frame(width: 160, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(localizedName(for: key))
                    .frame(width: 160, alignment: .leading)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                valueEditor(for: key, value: value)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(key)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(localizedName(for: key))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                valueEditor(for: key, value: value)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func valueEditor(for key: String, value: String) -> some View {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "true" || normalized == "false" {
            return AnyView(
                Toggle("", isOn: Binding(
                    get: { normalized == "true" },
                    set: { newValue in
                        properties[key] = newValue ? "true" : "false"
                        markPropertiesDirtyAndAutoSave()
                    }
                ))
                .labelsHidden()
            )
        }
        return AnyView(
            TextField("", text: Binding(
                get: { properties[key] ?? "" },
                set: { newValue in
                    properties[key] = newValue
                    markPropertiesDirtyAndAutoSave()
                }
            ))
            .textFieldStyle(.roundedBorder)
        )
    }

    func markPropertiesDirtyAndAutoSave() {
        isDirty = true
        propertiesAutoSaveTask?.cancel()
        propertiesAutoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                save()
            }
        }
    }

    func localizedName(for key: String) -> String {
        switch key {
        case "server-port": return "server.properties.name.server-port".localized()
        case "server-ip": return "server.properties.name.server-ip".localized()
        case "online-mode": return "server.properties.name.online-mode".localized()
        case "enable-command-block": return "server.properties.name.enable-command-block".localized()
        case "view-distance": return "server.properties.name.view-distance".localized()
        case "simulation-distance": return "server.properties.name.simulation-distance".localized()
        case "max-players": return "server.properties.name.max-players".localized()
        case "motd": return "server.properties.name.motd".localized()
        case "level-name": return "server.properties.name.level-name".localized()
        case "level-seed": return "server.properties.name.level-seed".localized()
        case "level-type": return "server.properties.name.level-type".localized()
        case "difficulty": return "server.properties.name.difficulty".localized()
        case "gamemode": return "server.properties.name.gamemode".localized()
        case "pvp": return "server.properties.name.pvp".localized()
        case "allow-flight": return "server.properties.name.allow-flight".localized()
        case "spawn-protection": return "server.properties.name.spawn-protection".localized()
        case "white-list": return "server.properties.name.white-list".localized()
        case "enforce-whitelist": return "server.properties.name.enforce-whitelist".localized()
        case "generate-structures": return "server.properties.name.generate-structures".localized()
        case "allow-nether": return "server.properties.name.allow-nether".localized()
        case "hardcore": return "server.properties.name.hardcore".localized()
        case "max-world-size": return "server.properties.name.max-world-size".localized()
        case "resource-pack": return "server.properties.name.resource-pack".localized()
        case "resource-pack-sha1": return "server.properties.name.resource-pack-sha1".localized()
        case "enable-status": return "server.properties.name.enable-status".localized()
        case "broadcast-rcon-to-ops": return "server.properties.name.broadcast-rcon-to-ops".localized()
        case "broadcast-console-to-ops": return "server.properties.name.broadcast-console-to-ops".localized()
        case "enable-rcon": return "server.properties.name.enable-rcon".localized()
        case "rcon.port": return "server.properties.name.rcon.port".localized()
        case "rcon.password": return "server.properties.name.rcon.password".localized()
        case "enable-query": return "server.properties.name.enable-query".localized()
        case "query.port": return "server.properties.name.query.port".localized()
        case "prevent-proxy-connections": return "server.properties.name.prevent-proxy-connections".localized()
        case "use-native-transport": return "server.properties.name.use-native-transport".localized()
        case "hide-online-players": return "server.properties.name.hide-online-players".localized()
        case "spawn-monsters": return "server.properties.name.spawn-monsters".localized()
        case "spawn-animals": return "server.properties.name.spawn-animals".localized()
        case "spawn-npcs": return "server.properties.name.spawn-npcs".localized()
        case "spawn-protection-radius": return "server.properties.name.spawn-protection-radius".localized()
        default: return key
        }
    }
}
