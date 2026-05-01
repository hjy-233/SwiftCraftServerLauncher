import Foundation

@MainActor
final class ServerDetailWindowCoordinator: ObservableObject {
    static let shared = ServerDetailWindowCoordinator()

    @Published private(set) var preferredSections: [String: String] = [:]

    private init() {}

    func open(serverId: String, preferredSection: String? = nil) {
        preferredSections[serverId] = preferredSection ?? "console"
        ServerDetailWindowManager.shared.open(serverId: serverId)
    }

    func consumePreferredSection(for serverId: String) -> String {
        preferredSections[serverId] ?? "console"
    }
}
