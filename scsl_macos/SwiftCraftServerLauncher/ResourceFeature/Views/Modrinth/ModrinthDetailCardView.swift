import Foundation
import SwiftUI

struct ModrinthDetailCardView: View {
    var project: ModrinthProject
    let selectedVersions: [String]
    let selectedLoaders: [String]
    let gameInfo: GameVersionInfo?
    let query: String
    let type: Bool
    @Binding var selectedItem: SidebarItem
    var onResourceChanged: (() -> Void)?
    var onLocalDisableStateChanged: ((ModrinthProject, Bool) -> Void)?
    var onResourceUpdated: ((String, String, String, String?) -> Void)?
    @Binding var scannedDetailIds: Set<String>
    @State private var isResourceDisabled = false
    @ObservedObject private var bookmarkStore = ResourceBookmarkStore.shared
    @EnvironmentObject private var gameRepository: GameRepository
    @EnvironmentObject private var generalSettings: GeneralSettingsManager

    enum AddButtonState {
        case idle
        case loading
        case installed
        case update
    }

    private var metrics: ResourceCardMetrics {
        ResourceCardMetrics(style: generalSettings.resourceCardStyle)
    }

    var body: some View {
        Group {
            switch generalSettings.resourceCardStyle {
            case .compact:
                compactContent
            case .card:
                cardContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isResourceDisabled ? 0.5 : 1.0)
        .onAppear {
            isResourceDisabled = ResourceEnableDisableManager.isDisabled(
                fileName: project.fileName
            )
        }
        .onChange(of: project.fileName) { _, newFileName in
            isResourceDisabled = ResourceEnableDisableManager.isDisabled(
                fileName: newFileName
            )
        }
    }

    private var compactContent: some View {
        HStack(alignment: .center, spacing: metrics.contentSpacing) {
            iconView

            VStack(alignment: .leading, spacing: 6) {
                Text(project.title)
                    .font(.headline)
                    .lineLimit(metrics.titleLineLimit)

                Text(project.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(metrics.descriptionLineLimit)
            }

            Spacer(minLength: 8)
            bookmarkButton
            installButton
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: metrics.contentSpacing) {
                iconView

                VStack(alignment: .leading, spacing: 8) {
                    Text(project.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(metrics.titleLineLimit)

                    Text(project.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(metrics.descriptionLineLimit)
                }
            }

            HStack {
                categoryChips(maxCount: 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                bookmarkButton
                installButton
            }

            Divider()
        }
    }

    private var iconView: some View {
        Group {
            if isLocalPlaceholderResource {
                localResourceIcon
            } else if let iconUrl = project.iconUrl,
                let url = URL(string: iconUrl) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholderIcon
                }
                .frame(width: metrics.iconSize, height: metrics.iconSize)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: metrics.cornerRadius,
                        style: .continuous
                    )
                )
            } else {
                placeholderIcon
            }
        }
    }

    private var placeholderIcon: some View {
        RoundedRectangle(
            cornerRadius: metrics.cornerRadius,
            style: .continuous
        )
        .fill(.quaternary)
        .frame(width: metrics.iconSize, height: metrics.iconSize)
    }

    private var localResourceIcon: some View {
        RoundedRectangle(
            cornerRadius: metrics.cornerRadius,
            style: .continuous
        )
        .fill(.quaternary)
        .frame(width: metrics.iconSize, height: metrics.iconSize)
        .overlay {
            Image(systemName: "internaldrive")
                .font(.system(size: metrics.iconSize * 0.32, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func categoryChips(maxCount: Int) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(project.displayCategories.prefix(maxCount)), id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, metrics.tagHorizontalPadding)
                    .padding(.vertical, metrics.tagVerticalPadding)
                    .background(.quinary, in: Capsule())
            }

            if project.displayCategories.count > maxCount {
                Text("+\(project.displayCategories.count - maxCount)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var installButton: some View {
        AddOrDeleteResourceButton(
            project: project,
            selectedVersions: selectedVersions,
            selectedLoaders: selectedLoaders,
            gameInfo: gameInfo,
            query: query,
            type: type,
            selectedItem: $selectedItem,
            onResourceChanged: onResourceChanged,
            scannedDetailIds: $scannedDetailIds,
            isResourceDisabled: $isResourceDisabled,
            onResourceUpdated: onResourceUpdated,
            onToggleDisableState: { isDisabled in
                onLocalDisableStateChanged?(project, isDisabled)
            },
            usesAppStoreStyle: true,
            usesSubtleAppStoreStyle: generalSettings.resourceCardStyle == .compact
        )
        .environmentObject(gameRepository)
    }

    private var bookmarkButton: some View {
        Button {
            bookmarkStore.toggle(project)
        } label: {
            Image(systemName: bookmarkStore.isBookmarked(project) ? "bookmark.fill" : "bookmark")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(bookmarkStore.isBookmarked(project) ? Color.accentColor : Color.secondary)
        .help(
            bookmarkStore.isBookmarked(project)
                ? "resource.bookmark.remove".localized()
                : "resource.bookmark.add".localized()
        )
        .disabled(!bookmarkStore.canBookmark(project))
    }

    private var isLocalPlaceholderResource: Bool {
        project.projectId.hasPrefix("local_") || project.projectId.hasPrefix("file_")
    }
}

@MainActor
final class ResourceBookmarkStore: ObservableObject {
    static let shared = ResourceBookmarkStore()

    @Published private(set) var projects: [ModrinthProject]

    private let storageKey = "resource.bookmarked.projects"

    private init() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ModrinthProject].self, from: data) else {
            projects = []
            return
        }
        projects = decoded
    }

    func canBookmark(_ project: ModrinthProject) -> Bool {
        project.projectType == ResourceType.mod.rawValue
            || project.projectType == ResourceType.plugin.rawValue
    }

    func isBookmarked(_ project: ModrinthProject) -> Bool {
        projects.contains { $0.projectId == project.projectId }
    }

    func toggle(_ project: ModrinthProject) {
        guard canBookmark(project) else { return }
        if let index = projects.firstIndex(where: { $0.projectId == project.projectId }) {
            projects.remove(at: index)
        } else {
            projects.insert(project, at: 0)
        }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
