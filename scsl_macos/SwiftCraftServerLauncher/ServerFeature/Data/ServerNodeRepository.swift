import Foundation

@MainActor
final class ServerNodeRepository: ObservableObject {
    @Published private(set) var nodes: [ServerNode] = []

    private var storageURL: URL {
        AppPaths.dataDirectory.appendingPathComponent("server_nodes.json")
    }

    init() {
        load()
    }

    func load() {
        try? FileManager.default.createDirectory(at: AppPaths.dataDirectory, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: storageURL),
           let decoded = try? JSONDecoder().decode([ServerNode].self, from: data) {
            let hasLocal = decoded.contains(where: \.isLocal)
            nodes = hasLocal ? decoded : [ServerNode.local] + decoded
        } else {
            nodes = [ServerNode.local]
            persist()
        }

        ensureNodeDirectories()
    }

    func addNode(_ node: ServerNode) {
        nodes.append(node)
        persist()
        ensureNodeDirectories()
    }

    func updateNode(_ node: ServerNode) {
        guard let idx = nodes.firstIndex(where: { $0.id == node.id }) else { return }
        nodes[idx] = node
        persist()
        ensureNodeDirectories()
    }

    func deleteNode(id: String) {
        guard let node = nodes.first(where: { $0.id == id }), !node.isLocal else { return }
        nodes.removeAll { $0.id == id }
        persist()
    }

    func getNode(by id: String) -> ServerNode? {
        nodes.first { $0.id == id }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(nodes)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            Logger.shared.error("保存节点失败: \(error.localizedDescription)")
        }
    }

    private func ensureNodeDirectories() {
        for node in nodes where !node.isLocal {
            let base = AppPaths.remoteNodeDirectory(nodeId: node.id)
            let servers = AppPaths.remoteNodeServersDirectory(nodeId: node.id)
            let data = AppPaths.remoteNodeDataDirectory(nodeId: node.id)
            let logs = AppPaths.remoteNodeLogsDirectory(nodeId: node.id)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: servers, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        }
    }
}
