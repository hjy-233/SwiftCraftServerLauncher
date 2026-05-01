import Foundation

enum MirrorSourceKind: String, Codable, CaseIterable, Identifiable {
    case fastMirror
    case polars
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fastMirror:
            return "settings.mirror.type.fastmirror".localized()
        case .polars:
            return "settings.mirror.type.polars".localized()
        case .custom:
            return "settings.mirror.type.custom_url".localized()
        }
    }
}

struct MirrorSourceConfig: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var kind: MirrorSourceKind
    var baseURL: String
    var customJSON: String?
    var isEnabled: Bool
    var isBuiltIn: Bool

    init(
        id: UUID = UUID(),
        name: String,
        kind: MirrorSourceKind,
        baseURL: String,
        customJSON: String? = nil,
        isEnabled: Bool = true,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.customJSON = customJSON
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
    }
}

final class MirrorSourceSettingsManager: ObservableObject {
    static let shared = MirrorSourceSettingsManager()

    @Published var sources: [MirrorSourceConfig] = [] {
        didSet {
            persistSources()
        }
    }

    private let storageKey = "mirrorSources"

    private init() {
        loadSources()
    }

    var enabledSources: [MirrorSourceConfig] {
        sources.filter { $0.isEnabled }
    }

    func addCustomSource() {
        let config = MirrorSourceConfig(
            name: "settings.mirror.custom.default_name".localized(),
            kind: .custom,
            baseURL: "https://",
            customJSON: MirrorCustomAPIConfig.defaultJSON,
            isEnabled: true,
            isBuiltIn: false
        )
        sources.append(config)
    }

    func removeSource(id: UUID) {
        sources.removeAll { $0.id == id }
    }

    private func loadSources() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([MirrorSourceConfig].self, from: data),
              !decoded.isEmpty else {
            sources = defaultSources()
            return
        }
        sources = decoded
    }

    private func persistSources() {
        guard let data = try? JSONEncoder().encode(sources) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func defaultSources() -> [MirrorSourceConfig] {
        [
            MirrorSourceConfig(
                name: ServerMirrorSource.fastMirror.displayName,
                kind: .fastMirror,
                baseURL: "https://download.fastmirror.net/api/v3",
                isEnabled: true,
                isBuiltIn: true
            ),
            MirrorSourceConfig(
                name: ServerMirrorSource.polars.displayName,
                kind: .polars,
                baseURL: "https://mirror.polars.cc/api/query/minecraft/core",
                isEnabled: true,
                isBuiltIn: true
            ),
        ]
    }
}
