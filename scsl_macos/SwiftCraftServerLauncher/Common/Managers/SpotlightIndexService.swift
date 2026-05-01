import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

final class SpotlightIndexService {
    static let shared = SpotlightIndexService()

    private let index = CSSearchableIndex.default()
    private let queue = DispatchQueue(label: "spotlight.index.queue", qos: .utility)
    private let clientStateKey = "spotlight.index.clientState"
    private let identifierPrefix = "commandPalette:"
    private let clientStateVersion = "v4"

    func ensureIndexedIfNeeded(nodes: [CommandPaletteNode]) {
        queue.async {
            let stored = UserDefaults.standard.string(forKey: self.clientStateKey)
            if stored != self.clientStateVersion {
                self.index.deleteSearchableItems(withDomainIdentifiers: ["commandPalette"]) { _ in
                    self.indexAll(nodes: nodes)
                }
            }
        }
    }

    func scheduleIndex(nodes: [CommandPaletteNode]) {
        queue.async {
            self.index.deleteSearchableItems(withDomainIdentifiers: ["commandPalette"]) { _ in
                self.indexAll(nodes: nodes)
            }
        }
    }

    private func indexAll(nodes: [CommandPaletteNode]) {
        let searchableNodes = collectSearchableNodes(from: nodes)
        let items = searchableNodes.map { node in
            let attributes = CSSearchableItemAttributeSet(contentType: .item)
            attributes.title = node.title
            attributes.contentDescription = node.subtitle
            attributes.keywords = node.keywords
            return CSSearchableItem(
                uniqueIdentifier: identifierPrefix + node.id,
                domainIdentifier: "commandPalette",
                attributeSet: attributes
            )
        }

        index.indexSearchableItems(items) { _ in
            UserDefaults.standard.set(self.clientStateVersion, forKey: self.clientStateKey)
        }
    }

    private func collectSearchableNodes(from nodes: [CommandPaletteNode]) -> [SearchableNode] {
        var results: [SearchableNode] = []
        for node in nodes {
            if isSearchable(node: node) {
                results.append(
                    SearchableNode(
                        id: node.id,
                        title: node.title,
                        subtitle: node.subtitle,
                        keywords: buildKeywords(node: node)
                    )
                )
            }
            if !node.children.isEmpty {
                results.append(contentsOf: collectSearchableNodes(from: node.children))
            }
        }
        return results
    }

    private func isSearchable(node: CommandPaletteNode) -> Bool {
        isServerRootNode(node.id)
    }

    private func isServerRootNode(_ id: String) -> Bool {
        guard id.hasPrefix("server:") else { return false }
        return id.split(separator: ":").count == 2
    }

    private func buildKeywords(node: CommandPaletteNode) -> [String] {
        var keywords: [String] = [node.title]
        if let subtitle = node.subtitle, !subtitle.isEmpty {
            keywords.append(subtitle)
        }
        return keywords
    }

    func stripIdentifierPrefix(_ identifier: String) -> String {
        if identifier.hasPrefix(identifierPrefix) {
            return String(identifier.dropFirst(identifierPrefix.count))
        }
        return identifier
    }
}

private struct SearchableNode {
    let id: String
    let title: String
    let subtitle: String?
    let keywords: [String]
}
