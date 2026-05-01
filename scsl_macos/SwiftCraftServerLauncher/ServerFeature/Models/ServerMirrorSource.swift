import Foundation

enum ServerMirrorSource: String, CaseIterable, Identifiable {
    case official
    case fastMirror
    case polars
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .official:
            return "server.form.mirror.official".localized()
        case .fastMirror:
            return "server.form.mirror.fastmirror".localized()
        case .polars:
            return "server.form.mirror.polars".localized()
        case .custom:
            return "server.form.mirror.custom".localized()
        }
    }

    var isAvailable: Bool {
        true
    }
}
