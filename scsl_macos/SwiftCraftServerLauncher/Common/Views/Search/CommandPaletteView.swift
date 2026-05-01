import SwiftUI

struct CommandPaletteNode: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let systemImage: String
    let children: [Self]
    let settingsTab: SettingsTab?
    let searchScope: CommandPaletteSearchScope?
    let searchOnly: Bool
    let resourceType: ResourceType?
    let action: (() -> Void)?

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        children: [Self] = [],
        settingsTab: SettingsTab? = nil,
        searchScope: CommandPaletteSearchScope? = nil,
        searchOnly: Bool = false,
        resourceType: ResourceType? = nil,
        action: (() -> Void)? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.children = children
        self.settingsTab = settingsTab
        self.searchScope = searchScope
        self.searchOnly = searchOnly
        self.resourceType = resourceType
        self.action = action
    }
}

enum CommandPaletteSearchScope {
    case resources
    case resourceType(ResourceType)
}

struct CommandPaletteView: View {
    let nodes: [CommandPaletteNode]

    @EnvironmentObject private var commandPalette: CommandPaletteController
    @Environment(\.openSettings)
    private var openSettings: OpenSettingsAction
    @EnvironmentObject private var settingsNavigation: SettingsNavigationManager
    @State private var selection: String?
    @State private var pendingScrollId: String?
    @FocusState private var isSearchFocused: Bool

    private var isSearching: Bool {
        !commandPalette.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var displayNodes: [CommandPaletteNode] {
        if isSearching {
            return searchResults
        }
        return nodes.filter { !$0.searchOnly }
    }

    private struct DisplayRow: Identifiable {
        let id: String
        let node: CommandPaletteNode?
        let title: String?
        let indent: CGFloat
        let isSelectable: Bool
    }

    private var displayRows: [DisplayRow] {
        if isSearching {
            return buildSearchRows()
        }

        var rows: [DisplayRow] = []
        rows.append(contentsOf: buildTreeRows(nodes: nodes.filter { !$0.searchOnly }, indent: 0))
        return rows
    }

    private var selectableRows: [DisplayRow] {
        displayRows.filter { $0.isSelectable }
    }

    private var searchResults: [CommandPaletteNode] {
        let trimmed = commandPalette.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lowercased = trimmed.lowercased()
        let flattened = flatten(nodes: searchScopeNodes, path: [])
        let filtered = flattened.filter { entry in
            matchesFilter(node: entry.node, query: lowercased)
        }
        let mapped = filtered.map { entry in
            let pathText = entry.path.joined(separator: " > ")
            let subtitle = pathText.isEmpty ? entry.node.subtitle : pathText
            return CommandPaletteNode(
                id: entry.node.id,
                title: entry.node.title,
                subtitle: subtitle,
                systemImage: entry.node.systemImage,
                children: entry.node.children,
                settingsTab: entry.node.settingsTab,
                searchScope: entry.node.searchScope,
                searchOnly: entry.node.searchOnly,
                resourceType: entry.node.resourceType,
                action: entry.node.action
            )
        }
        return mapped + resourceSearchNodesForScope()
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture {
                    commandPalette.dismiss()
                }

            VStack(spacing: 12) {
                searchFieldView

                if displayNodes.isEmpty {
                    emptyState
                } else {
                    actionListView
                }
            }
            .padding(16)
            .frame(width: 520, height: 420)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(NSColor.windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.black.opacity(0.12), lineWidth: 1)
            )
            .onTapGesture {}
        }
        .onAppear {
            isSearchFocused = true
            syncSelection()
        }
        .onChange(of: commandPalette.query) { _, _ in
            syncSelection()
        }
        .onChange(of: commandPalette.query) { oldValue, newValue in
            if oldValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                commandPalette.searchContextPath = commandPalette.pathIds
            }
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                commandPalette.searchContextPath = []
            }
        }
        .onChange(of: selection) { _, newValue in
            commandPalette.lastSelectionId = newValue
            pendingScrollId = newValue
            updatePathForSelection()
        }
        .onMoveCommand { direction in
            moveSelection(direction)
        }
        .onExitCommand {
            commandPalette.dismiss()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("command.palette.empty".localized())
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    private var searchFieldView: some View {
        TextField("command.palette.placeholder".localized(), text: $commandPalette.query)
            .textFieldStyle(.roundedBorder)
            .focused($isSearchFocused)
            .onSubmit {
                activateSelectedNode(primary: true)
            }
            .background(
                KeyEventHandlingView(isActive: Binding(
                    get: { isSearchFocused },
                    set: { isSearchFocused = $0 }
                )) { keyCode in
                    handleKeyDown(keyCode)
                }
            )
    }

    private var actionListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(displayRows) { row in
                        actionRow(for: row)
                            .id(row.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: selection) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
            .onChange(of: pendingScrollId) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func actionRow(for row: DisplayRow) -> some View {
        if let title = row.title {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
        } else if let node = row.node {
            Button {
                activateNode(node, primary: true)
            } label: {
                rowLabel(for: node, isSelected: node.id == selection, indent: row.indent)
            }
            .buttonStyle(.plain)
        } else {
            EmptyView()
        }
    }

    private func rowLabel(for node: CommandPaletteNode, isSelected: Bool, indent: CGFloat) -> some View {
        Group {
            if node.searchOnly, let resourceType = node.resourceType {
                resourceSearchRow(
                    title: node.title,
                    subtitle: commandPalette.query,
                    systemImage: resourceType.systemImage,
                    isSelected: isSelected
                )
            } else {
                basicRowLabel(for: node, isSelected: isSelected, indent: indent)
            }
        }
    }

    private func basicRowLabel(for node: CommandPaletteNode, isSelected: Bool, indent: CGFloat) -> some View {
        HStack(spacing: 12) {
            if !node.children.isEmpty {
                Image(systemName: commandPalette.expandedIds.contains(node.id) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 12)
            } else {
                Color.clear
                    .frame(width: 12)
            }
            Image(systemName: node.systemImage)
                .frame(width: 18)
                .foregroundColor(.secondary)
            Text(node.title)
                .foregroundColor(.primary)
            Spacer()
            shortcutBadges(for: node)
                .opacity(isSelected ? 1 : 0)
                .frame(width: 110, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .padding(.leading, indent)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
    }

    private func resourceSearchRow(
        title: String,
        subtitle: String,
        systemImage: String,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 22))
                .frame(width: 36, height: 36)
                .background(Color.gray.opacity(0.12))
                .cornerRadius(8)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("command.palette.action.show_more".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.18))
                .clipShape(Capsule())
            shortcutBadges(for: nil)
                .opacity(isSelected ? 1 : 0)
                .frame(width: 110, alignment: .trailing)
            // no inline controls for search-only resource entries
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
    }

    private func activateSelectedNode(primary: Bool) {
        guard let node = selectableRows.first(where: { $0.id == selection })?.node
            ?? selectableRows.first?.node else { return }
        activateNode(node, primary: primary)
    }

    private func activateNode(_ node: CommandPaletteNode, primary: Bool) {
        if primary {
            if node.id == "settings" {
                commandPalette.dismiss()
                settingsNavigation.selectedTab = .general
                openSettings()
                return
            }
            if let tab = node.settingsTab {
                commandPalette.dismiss()
                settingsNavigation.selectedTab = tab
                openSettings()
                return
            }
            if let action = node.action {
                commandPalette.dismiss()
                action()
                return
            }
            if !node.children.isEmpty {
                expandNode(node, focusFirstChild: true)
            }
            return
        }

        if !node.children.isEmpty {
            expandNode(node, focusFirstChild: true)
            return
        }

        if primary {
            commandPalette.dismiss()
        }
    }

    private func shortcutBadge(text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.gray.opacity(0.18))
            .clipShape(Capsule())
    }

    private func shortcutBadges(for node: CommandPaletteNode?) -> some View {
        HStack(spacing: 6) {
            if let node, !node.children.isEmpty, node.settingsTab != nil || node.action != nil || node.id == "settings" {
                shortcutBadge(text: "↩ 打开")
                shortcutBadge(text: "→ 展开")
            } else if let node, !node.children.isEmpty {
                shortcutBadge(text: "→ 展开")
            } else {
                shortcutBadge(text: "↩ 打开")
            }
        }
    }

    private func expandNode(_ node: CommandPaletteNode, focusFirstChild: Bool) {
        commandPalette.expandedIds.insert(node.id)
        if focusFirstChild, let firstChild = node.children.first {
            selection = firstChild.id
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !selectableRows.isEmpty else { return }
        let currentIndex = selectableRows.firstIndex { $0.id == selection } ?? 0
        let nextIndex: Int

        switch direction {
        case .up:
            nextIndex = max(currentIndex - 1, 0)
        case .down:
            nextIndex = min(currentIndex + 1, selectableRows.count - 1)
        default:
            return
        }

        selection = selectableRows[nextIndex].id
        isSearchFocused = true
    }

    private func handleKeyDown(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 123:
            if commandPalette.query.isEmpty {
                collapseOrMoveToParent()
                return true
            }
            return false
        case 124:
            if commandPalette.query.isEmpty {
                expandOrMoveIntoChild()
                return true
            }
            return false
        case 125:
            moveSelection(.down)
            return true
        case 126:
            moveSelection(.up)
            return true
        case 36, 76:
            activateSelectedNode(primary: true)
            return true
        case 49:
            let hasChildren = selectableRows.contains {
                $0.id == selection && $0.node?.children.isEmpty == false
            }
            activateSelectedNode(primary: !hasChildren)
            return true
        case 51:
            if commandPalette.query.isEmpty {
                collapseOrMoveToParent()
                return true
            }
            return false
        default:
            return false
        }
    }

    private func syncSelection() {
        if let lastSelection = commandPalette.lastSelectionId,
           selectableRows.contains(where: { $0.id == lastSelection }) {
            selection = lastSelection
        } else {
            selection = selectableRows.first?.id
        }
    }

    private func matchesFilter(node: CommandPaletteNode, query: String) -> Bool {
        if node.title.lowercased().contains(query) {
            return true
        }
        if let subtitle = node.subtitle?.lowercased() {
            return subtitle.contains(query)
        }
        return false
    }

    private var breadcrumbNodes: [CommandPaletteNode] {
        if isSearching, !commandPalette.searchContextPath.isEmpty {
            return pathFromIds(commandPalette.searchContextPath)
        }
        guard let selection else { return [] }
        return findPath(to: selection, in: nodes) ?? []
    }

    private var searchScopeNodes: [CommandPaletteNode] {
        guard let scopeNode = searchScopeNode else { return nodes.filter { !$0.searchOnly } }
        switch scopeNode.searchScope {
        case .resources:
            return scopeNode.children.filter { !$0.searchOnly }
        case .resourceType(let type):
            if let resourcesNode = nodes.first(where: { $0.id == "resources" }) {
                return resourcesNode.children.filter { $0.id == "resource:\(type.rawValue)" }
            }
            return []
        case .none:
            return nodes.filter { !$0.searchOnly }
        }
    }

    private var searchScopeNode: CommandPaletteNode? {
        for node in breadcrumbNodes.reversed() where node.searchScope != nil {
            return node
        }
        return nil
    }

    private func resourceSearchNodesForScope() -> [CommandPaletteNode] {
        let allSearchNodes = nodes.filter { $0.searchOnly }
        guard let scopeNode = searchScopeNode else { return allSearchNodes }
        switch scopeNode.searchScope {
        case .resources:
            return allSearchNodes
        case .resourceType(let type):
            return allSearchNodes.filter { $0.resourceType == type }
        case .none:
            return allSearchNodes
        }
    }

    private func buildSearchRows() -> [DisplayRow] {
        let regularNodes = searchResults.filter { !$0.searchOnly }
        let resourceNodes = searchResults.filter { $0.searchOnly }

        var rows: [DisplayRow] = regularNodes.map { node in
            DisplayRow(
                id: node.id,
                node: node,
                title: nil,
                indent: 0,
                isSelectable: true
            )
        }

        if !resourceNodes.isEmpty {
            rows.append(
                DisplayRow(
                    id: "search-section-resources",
                    node: nil,
                    title: "command.palette.section.resources".localized(),
                    indent: 0,
                    isSelectable: false
                )
            )
            rows.append(contentsOf: resourceNodes.map { node in
                DisplayRow(
                    id: node.id,
                    node: node,
                    title: nil,
                    indent: 0,
                    isSelectable: true
                )
            })
        }

        return rows
    }

    private func buildTreeRows(nodes: [CommandPaletteNode], indent: CGFloat) -> [DisplayRow] {
        var rows: [DisplayRow] = []
        for node in nodes {
            rows.append(
                DisplayRow(
                    id: node.id,
                    node: node,
                    title: nil,
                    indent: indent,
                    isSelectable: true
                )
            )
            if commandPalette.expandedIds.contains(node.id) && !node.children.isEmpty {
                rows.append(contentsOf: buildTreeRows(nodes: node.children, indent: indent + 16))
            }
        }
        return rows
    }

    private func findPath(to targetId: String, in nodes: [CommandPaletteNode]) -> [CommandPaletteNode]? {
        for node in nodes {
            if node.id == targetId {
                return [node]
            }
            if let childPath = findPath(to: targetId, in: node.children) {
                return [node] + childPath
            }
        }
        return nil
    }

    private func collapseOrMoveToParent() {
        guard let selection, let path = findPath(to: selection, in: nodes), !path.isEmpty else { return }
        if let current = path.last, commandPalette.expandedIds.contains(current.id) {
            commandPalette.expandedIds.remove(current.id)
            return
        }
        guard path.count > 1 else { return }
        self.selection = path[path.count - 2].id
    }

    private func expandOrMoveIntoChild() {
        guard let selection, let current = selectableRows.first(where: { $0.id == selection })?.node else { return }
        guard !current.children.isEmpty else { return }
        if commandPalette.expandedIds.contains(current.id) {
            self.selection = current.children.first?.id
        } else {
            commandPalette.expandedIds.insert(current.id)
        }
    }

    private func updatePathForSelection() {
        guard let selection, let path = findPath(to: selection, in: nodes) else {
            commandPalette.pathIds = []
            return
        }
        commandPalette.pathIds = path.map { $0.id }
        var expanded = commandPalette.expandedIds
        for node in path.dropLast() where !node.children.isEmpty {
            expanded.insert(node.id)
        }
        commandPalette.expandedIds = expanded
        if isSearching, commandPalette.searchContextPath.isEmpty {
            commandPalette.searchContextPath = path.map { $0.id }
        }
    }

    private func pathFromIds(_ ids: [String]) -> [CommandPaletteNode] {
        var result: [CommandPaletteNode] = []
        var current = nodes
        for id in ids {
            guard let next = current.first(where: { $0.id == id }) else { break }
            result.append(next)
            current = next.children
        }
        return result
    }

    private func flatten(
        nodes: [CommandPaletteNode],
        path: [String]
    ) -> [(node: CommandPaletteNode, path: [String])] {
        var results: [(node: CommandPaletteNode, path: [String])] = []
        for node in nodes {
            results.append((node, path))
            if !node.children.isEmpty {
                let nextPath = path + [node.title]
                results.append(contentsOf: flatten(nodes: node.children, path: nextPath))
            }
        }
        return results
    }
}

private struct KeyEventHandlingView: NSViewRepresentable {
    @Binding var isActive: Bool
    let onKeyDown: (UInt16) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isActive: $isActive, onKeyDown: onKeyDown)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.start()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isActive = isActive
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var isActive: Bool
        private let onKeyDown: (UInt16) -> Bool
        private var monitor: Any?

        init(isActive: Binding<Bool>, onKeyDown: @escaping (UInt16) -> Bool) {
            self.isActive = isActive.wrappedValue
            self.onKeyDown = onKeyDown
        }

        func start() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isActive else { return event }
                if self.onKeyDown(event.keyCode) {
                    return nil
                }
                return event
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
    }
}
