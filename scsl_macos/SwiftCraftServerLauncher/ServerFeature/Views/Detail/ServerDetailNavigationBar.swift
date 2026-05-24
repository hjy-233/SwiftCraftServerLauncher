import AppKit
import SwiftUI

struct ServerDetailNavigationBar: View {
    let server: ServerInstance

    @EnvironmentObject private var detailState: ResourceDetailState
    @StateObject private var generalSettings = GeneralSettingsManager.shared

    private var enabledSections: [ServerDetailSectionItem] {
        ServerDetailSectionProvider.items(for: server, settings: generalSettings)
            .filter(\.isEnabled)
    }

    private var currentSectionBinding: Binding<String> {
        Binding(
            get: { detailState.serverPanelSection },
            set: { detailState.serverPanelSection = $0 }
        )
    }

    var body: some View {
        simpleModePicker
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            normalizeCurrentSection()
        }
        .onChange(of: server.id) { _, _ in
            normalizeCurrentSection()
        }
    }

    private var simpleModePicker: some View {
        Picker("", selection: currentSectionBinding) {
            ForEach(enabledSections) { item in
                Label(item.title, systemImage: item.icon)
                    .labelStyle(.titleAndIcon)
                    .tag(item.section.rawValue)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(maxWidth: 760, alignment: .leading)
    }

    private func normalizeCurrentSection() {
        let allowed = enabledSections.map(\.section.rawValue)
        if !allowed.contains(detailState.serverPanelSection) {
            detailState.serverPanelSection = allowed.first ?? ServerDetailSection.console.rawValue
        }
    }
}

struct WorkspaceTabItem: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
    let minWidth: CGFloat
    let maxWidth: CGFloat
}

struct WorkspaceTabsStripView<LeadingContent: View, TrailingContent: View>: View {
    let tabs: [WorkspaceTabItem]
    let activeTabId: String?
    let onActivate: (String) -> Void
    let onClose: (String) -> Void
    @ViewBuilder var leadingContent: () -> LeadingContent
    @ViewBuilder var trailingContent: () -> TrailingContent
    @State private var hoveredTabId: String?

    var body: some View {
        HStack(spacing: 0) {
            InteractiveHorizontalScrollView {
                HStack(spacing: 0) {
                    ForEach(tabs) { tab in
                        workspaceTabButton(tab)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity)
            .layoutPriority(1)

            HStack(spacing: 0) {
                leadingContent()
                trailingContent()
            }
            .fixedSize()
        }
        .frame(height: 26)
    }

    private func workspaceTabButton(_ tab: WorkspaceTabItem) -> some View {
        let isActive = tab.id == activeTabId
        return ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: tab.systemImage)
                        .foregroundStyle(isActive ? Color.white.opacity(0.85) : .secondary)
                    Text(tab.title)
                        .lineLimit(1)
                        .font(.body.weight(.semibold))
                }
                .padding(.leading, 11)
                .padding(.trailing, 24)
                .frame(
                    minWidth: tab.minWidth,
                    maxWidth: tab.maxWidth,
                    minHeight: 26,
                    maxHeight: 26,
                    alignment: .leading
                )
                .foregroundStyle(isActive ? Color.white.opacity(0.92) : .primary)
                .contentShape(Rectangle())
            }
            .onTapGesture {
                onActivate(tab.id)
            }
            .accessibilityAddTraits(.isButton)
            .zIndex(1)

            Image(systemName: "xmark")
                .font(.caption2)
                .frame(width: 22, height: 26)
                .contentShape(Rectangle())
                .onTapGesture {
                    onClose(tab.id)
                }
                .accessibilityAddTraits(.isButton)
                .foregroundStyle(isActive ? Color.white.opacity(0.65) : .secondary)
                .opacity(hoveredTabId == tab.id ? 1 : 0)
                .allowsHitTesting(hoveredTabId == tab.id)
                .zIndex(2)
        }
        .overlay(alignment: .trailing) {
            Divider()
                .frame(height: 16)
                .opacity(isActive ? 0 : 1)
        }
        .background(isActive ? Color.accentColor.opacity(0.52) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovering in
            hoveredTabId = isHovering ? tab.id : nil
        }
    }
}

private struct InteractiveHorizontalScrollView<Content: View>: NSViewRepresentable {
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .automatic

        let hostingView = NSHostingView(rootView: content())
        hostingView.frame = NSRect(origin: .zero, size: hostingView.fittingSize)
        context.coordinator.hostingView = hostingView
        scrollView.documentView = hostingView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let hostingView = context.coordinator.hostingView ?? NSHostingView(rootView: content())
        context.coordinator.hostingView = hostingView
        hostingView.rootView = content()
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: fittingSize.width, height: max(26, fittingSize.height))
        )
        if scrollView.documentView !== hostingView {
            scrollView.documentView = hostingView
        }
    }

    final class Coordinator {
        var hostingView: NSHostingView<Content>?
    }
}
