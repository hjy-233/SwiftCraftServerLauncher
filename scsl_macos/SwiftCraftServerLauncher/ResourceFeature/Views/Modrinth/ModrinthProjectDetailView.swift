import AppKit
import SwiftMarkDownUI
import SwiftUI

// MARK: - Constants
private enum Constants {
    static let iconSize: CGFloat = 75
    static let cornerRadius: CGFloat = 8
    static let spacing: CGFloat = 12
    static let padding: CGFloat = 16
    static let galleryImageHeight: CGFloat = 160
    static let galleryImageMinWidth: CGFloat = 160
    static let galleryImageMaxWidth: CGFloat = 200
    static let categorySpacing: CGFloat = 6
    static let categoryPadding: CGFloat = 4
    static let categoryVerticalPadding: CGFloat = 2
    static let categoryCornerRadius: CGFloat = 12
    static let headerGradientHeight: CGFloat = 170
    static let headerTopOffset: CGFloat = 5
    static let metadataItemMinWidth: CGFloat = 120
    static let detailsSidebarWidth: CGFloat = 360
    static let maxVisibleSidebarVersions = 15
}

enum ResourceDetailSection: Hashable {
    case versions
    case loaders
    case platform
    case type
    case links
    case details
}

// MARK: - ModrinthProjectDetailView
struct ModrinthProjectDetailView: View {
    let projectDetail: ModrinthProjectDetail?
    let projectSummary: ModrinthProject?
    let selectedItem: Binding<SidebarItem>
    let onRequestDetailSection: (ResourceDetailSection) -> Void
    @Environment(\.colorScheme)
    private var colorScheme
    @ObservedObject private var bookmarkStore = ResourceBookmarkStore.shared
    @State private var iconAccentColor: Color?
    @State private var scannedDetailIds: Set<String> = []
    @State private var isResourceDisabled = false
    @State private var isShowingVersionDetails = false

    init(
        projectDetail: ModrinthProjectDetail?,
        projectSummary: ModrinthProject?,
        selectedItem: Binding<SidebarItem>,
        onRequestDetailSection: @escaping (ResourceDetailSection) -> Void = { _ in }
    ) {
        self.projectDetail = projectDetail
        self.projectSummary = projectSummary
        self.selectedItem = selectedItem
        self.onRequestDetailSection = onRequestDetailSection
    }

    var body: some View {
        if let project = projectDetail {
            projectDetailView(project)
                .task(id: iconURLString(for: project)) {
                    await updateIconAccentColor(from: iconURLString(for: project))
                }
        } else {
            loadingView
        }
    }

    // MARK: - Project Detail View
    private func projectDetailView(_ project: ModrinthProjectDetail) -> some View {
        ZStack(alignment: .topLeading) {
            pageBackground
            headerBackground

            VStack(alignment: .leading, spacing: 0) {
                projectHeader(project)
                projectMetadataBar(project)
                projectContent(project)
            }
            .padding(.top, Constants.headerTopOffset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    private var pageBackground: some View {
        (iconAccentColor ?? .accentColor)
            .opacity(colorScheme == .dark ? 0.1 : 0.05)
            .ignoresSafeArea()
    }

    private var headerBackground: some View {
        LinearGradient(
            colors: [
                (iconAccentColor ?? .accentColor).opacity(0.35),
                (iconAccentColor ?? .accentColor).opacity(0.14),
                .clear,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: Constants.headerGradientHeight)
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Project Header
    private func projectHeader(_ project: ModrinthProjectDetail) -> some View {
        HStack(alignment: .top, spacing: 18) {
            projectIcon(project)

            VStack(alignment: .leading, spacing: Constants.spacing) {
                Text(project.title)
                    .font(.largeTitle.bold())
                    .lineLimit(2)

                headerTags(project)

                HStack(spacing: 14) {
                    installButton(for: project)
                    bookmarkButton(for: project)
                }
            }
        }
        .padding(.horizontal, Constants.padding)
        .padding(.vertical, Constants.spacing)
    }

    private func projectIcon(_ project: ModrinthProjectDetail) -> some View {
        Group {
            if let iconUrl = iconURLString(for: project),
               let url = URL(string: iconUrl.httpToHttps()) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: Constants.iconSize, height: Constants.iconSize)
                            .clipped()
                    case .empty:
                        projectIconPlaceholder
                    case .failure:
                        projectIconPlaceholder
                    @unknown default:
                        projectIconPlaceholder
                    }
                }
            } else {
                projectIconPlaceholder
            }
        }
        .frame(width: Constants.iconSize, height: Constants.iconSize)
        .clipShape(
            RoundedRectangle(
                cornerRadius: Constants.cornerRadius,
                style: .continuous
            )
        )
    }

    private var projectIconPlaceholder: some View {
        RoundedRectangle(
            cornerRadius: Constants.cornerRadius,
            style: .continuous
        )
        .fill(.quaternary)
        .overlay {
            Image(systemName: "shippingbox")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .frame(width: Constants.iconSize, height: Constants.iconSize)
    }

    private func headerTags(_ project: ModrinthProjectDetail) -> some View {
        let summaryCategories = projectSummary?.displayCategories ?? []
        let categories = summaryCategories.isEmpty ? project.categories : summaryCategories

        return HStack(spacing: 8) {
            ForEach(Array(categories.prefix(4)), id: \.self) { category in
                Text(category)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quinary, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    private func installButton(for project: ModrinthProjectDetail) -> some View {
        AddOrDeleteResourceButton(
            project: summaryProject(for: project),
            selectedVersions: project.gameVersions,
            selectedLoaders: project.loaders,
            gameInfo: nil,
            query: project.projectType,
            type: true,
            selectedItem: selectedItem,
            scannedDetailIds: $scannedDetailIds,
            isResourceDisabled: $isResourceDisabled,
            usesAppStoreStyle: true
        )
    }

    private func bookmarkButton(for project: ModrinthProjectDetail) -> some View {
        let summaryProject = summaryProject(for: project)
        return Button {
            bookmarkStore.toggle(summaryProject)
        } label: {
            Image(systemName: bookmarkStore.isBookmarked(summaryProject) ? "bookmark.fill" : "bookmark")
                .font(.title3)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(bookmarkStore.isBookmarked(summaryProject) ? Color.accentColor : Color.secondary)
        .help(
            bookmarkStore.isBookmarked(summaryProject)
                ? "resource.bookmark.remove".localized()
                : "resource.bookmark.add".localized()
        )
        .disabled(!bookmarkStore.canBookmark(summaryProject))
    }

    private func iconURLString(for project: ModrinthProjectDetail) -> String? {
        project.iconUrl ?? projectSummary?.iconUrl
    }

    private func summaryProject(for project: ModrinthProjectDetail) -> ModrinthProject {
        let fallbackCategories = projectSummary?.displayCategories ?? []
        let displayCategories = project.additionalCategories ?? fallbackCategories

        return ModrinthProject(
            projectId: project.id,
            projectType: project.projectType,
            slug: project.slug,
            author: authorName(for: project),
            title: project.title,
            description: project.description,
            categories: project.categories,
            displayCategories: displayCategories,
            versions: project.gameVersions,
            downloads: project.downloads,
            follows: project.followers,
            iconUrl: iconURLString(for: project),
            license: project.license?.id ?? "",
            clientSide: project.clientSide,
            serverSide: project.serverSide,
            fileName: project.fileName
        )
    }

    private func authorName(for project: ModrinthProjectDetail) -> String {
        let summaryAuthor = projectSummary?.author.trimmingCharacters(in: .whitespacesAndNewlines)
        if let summaryAuthor, !summaryAuthor.isEmpty {
            return summaryAuthor
        }
        return project.team
    }

    // MARK: - Project Metadata
    private func projectMetadataBar(_ project: ModrinthProjectDetail) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                versionMetadataItem(project)
                metadataDivider
                platformMetadataItem(project)
                metadataDivider
                metadataItem(
                    section: .loaders,
                    help: "filter.loader".localized(),
                    value: listSummary(project.loaders),
                    systemImage: "switch.2"
                )
                metadataDivider
                typeMetadataItem(project)
                metadataDivider
                metadataItem(
                    section: .details,
                    help: "resource.detail.author".localized(),
                    value: authorName(for: project),
                    systemImage: "person.crop.square"
                )
            }
            .padding(.horizontal, Constants.padding)
            .padding(.vertical, 14)
            Divider()
        }
    }

    private var metadataDivider: some View {
        Divider()
            .frame(height: 72)
    }

    private func versionMetadataItem(_ project: ModrinthProjectDetail) -> some View {
        Button {
            onRequestDetailSection(.versions)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .help("filter.version".localized())
                VStack(spacing: 2) {
                    Text(versionRangeText(project.gameVersions))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    metadataCaption("resource.detail.version_details".localized())
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }

    private func platformMetadataItem(_ project: ModrinthProjectDetail) -> some View {
        Button {
            onRequestDetailSection(.platform)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: "desktopcomputer")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .help("platform.support".localized())
                HStack(spacing: 16) {
                    platformStatusIcon(
                        baseIcon: "laptopcomputer",
                        value: project.clientSide,
                        help: localizedPlatformValue(prefix: "platform.client", value: project.clientSide)
                    )
                    platformStatusIcon(
                        baseIcon: "server.rack",
                        value: project.serverSide,
                        help: localizedPlatformValue(prefix: "platform.server", value: project.serverSide)
                    )
                }
                metadataCaption("platform.support".localized())
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }

    private func platformStatusIcon(baseIcon: String, value: String, help: String) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: baseIcon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
            Image(systemName: platformStatusSymbol(for: value))
                .font(.caption2.weight(.bold))
                .foregroundStyle(platformStatusColor(for: value))
                .background(.background, in: Circle())
                .offset(x: 4, y: 4)
        }
        .help(help)
    }

    private func typeMetadataItem(_ project: ModrinthProjectDetail) -> some View {
        Button {
            onRequestDetailSection(.type)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: projectTypeIcon(for: project.projectType))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .help(localizedProjectType(project.projectType))

                Text(localizedProjectType(project.projectType))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                metadataCaption("resource.detail.type".localized())
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }

    private func metadataItem(
        section: ResourceDetailSection,
        help: String,
        value: String,
        systemImage: String
    ) -> some View {
        Button {
            onRequestDetailSection(section)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .help(help)
                Text(value)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                metadataCaption(help)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }

    private func metadataCaption(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func versionDetailsPopover(_ versions: [String]) -> some View {
        VersionGroupedView(
            items: versions.map { FilterItem(id: $0, name: $0) },
            selectedItems: .constant([])
        ) { _ in }
        .frame(width: 520, height: 620)
    }

    // MARK: - Project Content
    private func projectContent(_ project: ModrinthProjectDetail) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            descriptionView(project)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            Divider()

            projectSidebar(project)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, Constants.padding)
        .padding(.top, 18)
        .padding(.bottom, Constants.spacing)
    }

    private func descriptionView(_ project: ModrinthProjectDetail) -> some View {
        MixedMarkdownView(project.body)
    }

    private func projectSidebar(_ project: ModrinthProjectDetail) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            sidebarVersionsSection(project.gameVersions)
                .id(ResourceDetailSection.versions)
            sidebarLoadersSection(project.loaders)
                .id(ResourceDetailSection.loaders)
            sidebarPlatformSection(project)
                .id(ResourceDetailSection.platform)
            sidebarTypeSection(project)
                .id(ResourceDetailSection.type)
            sidebarLinksSection(project)
                .id(ResourceDetailSection.links)
            sidebarDetailsSection(project)
                .id(ResourceDetailSection.details)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sidebarVersionsSection(_ versions: [String]) -> some View {
        sidebarSection {
            HStack {
                sidebarSectionTitle("project.info.versions".localized())
                Spacer()
                if versions.count > Constants.maxVisibleSidebarVersions {
                    Button("+\(versions.count - Constants.maxVisibleSidebarVersions)") {
                        isShowingVersionDetails = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .popover(isPresented: $isShowingVersionDetails) {
                        versionDetailsPopover(versions)
                    }
                }
            }
        } content: {
            FlowLayout(spacing: 8) {
                ForEach(versionPreview(versions), id: \.self) { version in
                    sidebarPillButton(version) {}
                }
            }
        }
    }

    private func sidebarLoadersSection(_ loaders: [String]) -> some View {
        sidebarSection("project.info.platforms".localized()) {
            FlowLayout(spacing: 8) {
                ForEach(loaders, id: \.self) { loader in
                    sidebarPillButton(loader) {}
                }
            }
        }
    }

    private func sidebarPlatformSection(_ project: ModrinthProjectDetail) -> some View {
        sidebarSection("platform.support".localized()) {
            FlowLayout(spacing: 8) {
                sidebarPillButton(
                    localizedPlatformValue(prefix: "platform.client", value: project.clientSide),
                    systemImage: "laptopcomputer"
                ) {}
                sidebarPillButton(
                    localizedPlatformValue(prefix: "platform.server", value: project.serverSide),
                    systemImage: "server.rack"
                ) {}
            }
        }
    }

    private func sidebarTypeSection(_ project: ModrinthProjectDetail) -> some View {
        sidebarSection("resource.detail.type".localized()) {
            FlowLayout(spacing: 8) {
                sidebarPillButton(
                    localizedProjectType(project.projectType),
                    systemImage: projectTypeIcon(for: project.projectType)
                ) {}
                ForEach(project.categories, id: \.self) { category in
                    sidebarPillButton(category, systemImage: "tag") {}
                }
            }
        }
    }

    private func sidebarLinksSection(_ project: ModrinthProjectDetail) -> some View {
        let links = resourceLinks(for: project)
        return sidebarSection("project.info.links".localized()) {
            FlowLayout(spacing: 8) {
                ForEach(links) { link in
                    Button {
                        NSWorkspace.shared.open(link.url)
                    } label: {
                        Label(link.title, systemImage: link.systemImage)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func sidebarDetailsSection(_ project: ModrinthProjectDetail) -> some View {
        sidebarSection("project.info.details".localized()) {
            VStack(alignment: .leading, spacing: 8) {
                sidebarDetailRow(
                    label: "resource.detail.author".localized(),
                    value: authorName(for: project)
                )
                sidebarDetailRow(
                    label: "resource.detail.license".localized(),
                    value: project.license?.name ?? project.license?.id
                )
                sidebarDetailRow(
                    label: "resource.detail.downloads".localized(),
                    value: project.downloads.formatted()
                )
                sidebarDetailRow(
                    label: "resource.detail.followers".localized(),
                    value: project.followers.formatted()
                )
                sidebarDetailRow(
                    label: "resource.detail.published".localized(),
                    value: project.published.formatted(.relative(presentation: .named))
                )
                sidebarDetailRow(
                    label: "resource.detail.updated".localized(),
                    value: project.updated.formatted(.relative(presentation: .named))
                )
                sidebarDetailRow(label: "resource.detail.project_id".localized(), value: project.id)
                sidebarDetailRow(label: "resource.detail.slug".localized(), value: project.slug)
            }
        }
    }

    private func sidebarSection<Header: View, Content: View>(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header()
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sidebarSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        sidebarSection {
            sidebarSectionTitle(title)
        } content: {
            content()
        }
    }

    private func sidebarSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
    }

    private func sidebarPillButton(
        _ title: String,
        systemImage: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func sidebarDetailRow(label: String, value: String?) -> some View {
        LabeledContent(label) {
            Text(normalizedInfoValue(value))
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func versionPreview(_ versions: [String]) -> [String] {
        Array(versions.prefix(Constants.maxVisibleSidebarVersions))
    }

    private func resourceLinks(for project: ModrinthProjectDetail) -> [ResourceLink] {
        [
            ResourceLink(
                title: "project.info.links.issues".localized(),
                urlString: project.issuesUrl,
                systemImage: "exclamationmark.bubble"
            ),
            ResourceLink(
                title: "project.info.links.source".localized(),
                urlString: project.sourceUrl,
                systemImage: "chevron.left.forwardslash.chevron.right"
            ),
            ResourceLink(
                title: "project.info.links.wiki".localized(),
                urlString: project.wikiUrl,
                systemImage: "book"
            ),
            ResourceLink(
                title: "project.info.links.discord".localized(),
                urlString: project.discordUrl,
                systemImage: "bubble.left.and.bubble.right"
            ),
        ].compactMap { $0 }
    }

    private func normalizedInfoValue(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return "common.unknown".localized()
        }
        return trimmed
    }

    private func versionRangeText(_ versions: [String]) -> String {
        guard let newest = versions.first else {
            return "common.unknown".localized()
        }
        guard let oldest = versions.last, oldest != newest else {
            return newest
        }
        return "\(oldest) - \(newest)"
    }

    private func listSummary(_ values: [String]) -> String {
        guard !values.isEmpty else {
            return "common.unknown".localized()
        }
        return values.joined(separator: ", ")
    }

    private func platformSupportText(_ project: ModrinthProjectDetail) -> String {
        [
            localizedPlatformValue(prefix: "platform.client", value: project.clientSide),
            localizedPlatformValue(prefix: "platform.server", value: project.serverSide),
        ].joined(separator: " / ")
    }

    private func localizedPlatformValue(prefix: String, value: String) -> String {
        let key = "\(prefix).\(value)"
        let localized = key.localized()
        return localized == key ? value : localized
    }

    private func localizedProjectType(_ type: String) -> String {
        let key = "resource.content.type.\(type)"
        let localized = key.localized()
        return localized == key ? type : localized
    }

    private func projectTypeIcon(for type: String) -> String {
        switch type {
        case ProjectType.mod:
            return "shippingbox"
        case ProjectType.plugin:
            return "puzzlepiece.extension"
        case ProjectType.modpack:
            return "square.stack.3d.up"
        case ProjectType.datapack:
            return "doc.zipper"
        case ProjectType.resourcepack:
            return "paintpalette"
        case ProjectType.shader:
            return "sparkles"
        default:
            return "square.grid.2x2"
        }
    }

    private func platformStatusSymbol(for value: String) -> String {
        switch value {
        case "required":
            return "checkmark.circle.fill"
        case "optional":
            return "circle.dashed"
        case "unsupported":
            return "xmark.circle.fill"
        default:
            return "questionmark.circle.fill"
        }
    }

    private func platformStatusColor(for value: String) -> Color {
        switch value {
        case "required":
            return .green
        case "optional":
            return .orange
        case "unsupported":
            return .red
        default:
            return .secondary
        }
    }

    @MainActor
    private func updateIconAccentColor(from iconUrl: String?) async {
        guard let iconUrl, let url = URL(string: iconUrl) else {
            iconAccentColor = nil
            return
        }

        do {
            let image = try await ResourceImageCacheManager.shared.loadImage(from: url)
            iconAccentColor = image.averageVisibleColor.map(Color.init(nsColor:))
        } catch {
            iconAccentColor = nil
        }
    }

    // MARK: - Loading View
    private var loadingView: some View {
        VStack(alignment: .leading, spacing: Constants.spacing) {
            HStack(alignment: .top, spacing: 18) {
                SkeletonView(
                    width: Constants.iconSize,
                    height: Constants.iconSize,
                    cornerRadius: Constants.cornerRadius
                )

                VStack(alignment: .leading, spacing: Constants.spacing) {
                    SkeletonView(
                        width: SkeletonWidth.make(base: 320, variance: 60, seed: 101),
                        height: 36,
                        cornerRadius: 8
                    )
                    SkeletonView(
                        width: SkeletonWidth.make(base: 180, variance: 36, seed: 102),
                        height: 22,
                        cornerRadius: 6
                    )
                    HStack(spacing: 14) {
                        SkeletonView(
                            width: 67,
                            height: 23,
                            cornerRadius: 12
                        )
                        SkeletonView(
                            width: 28,
                            height: 28,
                            cornerRadius: 14
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(0..<8, id: \.self) { index in
                    SkeletonView(
                        width: SkeletonWidth.make(
                            base: 360 - CGFloat(index * 18),
                            variance: 52,
                            seed: 130 + index
                        ),
                        height: 12,
                        cornerRadius: 4
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Constants.padding)
    }
}

// MARK: - Helper Views
private struct CategoryTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, Constants.categoryPadding)
            .padding(.vertical, Constants.categoryVerticalPadding)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(Constants.categoryCornerRadius)
    }
}

private struct ResourceLink: Identifiable {
    let id: String
    let title: String
    let url: URL
    let systemImage: String

    init?(title: String, urlString: String?, systemImage: String) {
        guard let urlString, let url = URL(string: urlString) else {
            return nil
        }
        self.id = url.absoluteString
        self.title = title
        self.url = url
        self.systemImage = systemImage
    }
}

private extension NSImage {
    var averageVisibleColor: NSColor? {
        guard let bitmap = normalizedBitmap else { return nil }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 0, height > 0 else { return nil }

        var redTotal = 0.0
        var greenTotal = 0.0
        var blueTotal = 0.0
        var sampleCount = 0.0

        let stepX = max(width / 24, 1)
        let stepY = max(height / 24, 1)

        for x in stride(from: 0, to: width, by: stepX) {
            for y in stride(from: 0, to: height, by: stepY) {
                guard let color = bitmap.colorAt(x: x, y: y)?
                    .usingColorSpace(.sRGB) else {
                    continue
                }
                guard color.alphaComponent > 0.1 else { continue }

                redTotal += color.redComponent
                greenTotal += color.greenComponent
                blueTotal += color.blueComponent
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else { return nil }

        return NSColor(
            srgbRed: redTotal / sampleCount,
            green: greenTotal / sampleCount,
            blue: blueTotal / sampleCount,
            alpha: 1
        )
    }

    private var normalizedBitmap: NSBitmapImageRep? {
        guard let tiffRepresentation,
              let imageRep = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return imageRep
    }
}
