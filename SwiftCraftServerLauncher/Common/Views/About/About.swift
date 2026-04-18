import SwiftMarkDownUI
import SwiftUI

public struct AboutView: View {
    @Environment(\.openWindow)
    private var openWindow
    @State private var showingVersionHistory = false

    public init() {}

    // MARK: - Computed Properties
    private var appName: String { Bundle.main.appName }
    private var appVersion: String { Bundle.main.appVersion }
    private var buildNumber: String { Bundle.main.buildNumber }
    private var copyright: String { Bundle.main.copyright }

    public var body: some View {
        HStack(alignment: .center, spacing: 40) {
            appIconView

            VStack(alignment: .leading, spacing: 16) {
                titleSection
                footerSection
                actionButtons
            }
            .frame(width: 460, alignment: .leading)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 24)
        .frame(width: 720, height: 220)
    }

    private var footerSection: some View {
        Text(copyright)
            .foregroundStyle(.secondary)
            .font(.callout)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var appIconView: some View {
        Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
            .resizable()
            .frame(width: 118, height: 118)
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(appName)
                .font(.system(size: 34, weight: .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(String(format: "about.version.format".localized(), appVersion, buildNumber))
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    private var actionButtons: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                aboutButton("about.version_history".localized()) {
                    showingVersionHistory = true
                }
                aboutButton("about.github".localized()) {
                    openURL(URLConfig.API.GitHub.repositoryURL())
                }
            }
            GridRow {
                aboutButton("about.contributors".localized()) {
                    openWindow(id: WindowID.contributors.rawValue)
                }
                aboutButton("about.license".localized()) {
                    openURL(URLConfig.API.GitHub.licenseWebPage(ref: "dev"))
                }
            }
        }
        .sheet(isPresented: $showingVersionHistory) {
            VersionHistorySheetView(currentVersion: appVersion)
        }
    }

    private func aboutButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .lineLimit(1)
                .frame(width: 156, height: 18)
        }
        .controlSize(.small)
    }

    private func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

#Preview {
    AboutView()
}

private struct VersionHistorySheetView: View {
    let currentVersion: String

    @State private var releases: [GitHubRelease] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        CommonSheetView {
            HStack {
                Label("about.version_history".localized(), systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        } body: {
            content
                .frame(width: 560, height: 520)
                .task {
                    await loadReleasesIfNeeded()
                }
        } footer: {
            HStack {
                Text(String(format: "about.version_history.current".localized(), currentVersion))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("common.refresh".localized()) {
                    Task {
                        await loadReleases(force: true)
                    }
                }
                .disabled(isLoading)
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let errorMessage {
            ContentUnavailableView(
                "about.version_history.error".localized(),
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
        } else if isLoading && releases.isEmpty {
            VStack {
                ProgressView()
                    .controlSize(.large)
                Text("common.loading".localized())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if releases.isEmpty {
            ContentUnavailableView(
                "about.version_history.empty".localized(),
                systemImage: "tray"
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(releases) { release in
                        VersionHistoryCardView(
                            release: release,
                            isCurrent: release.tagName == currentVersion
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func loadReleasesIfNeeded() async {
        guard releases.isEmpty else { return }
        await loadReleases(force: false)
    }

    private func loadReleases(force _: Bool) async {
        isLoading = true
        errorMessage = nil
        do {
            releases = try await GitHubService.shared.fetchReleases()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct VersionHistoryCardView: View {
    let release: GitHubRelease
    let isCurrent: Bool

    @State private var showingDetails = false

    var body: some View {
        GroupBox {
            header
        }
        .groupBoxStyle(.automatic)
        .contentShape(Rectangle())
        .onTapGesture {
            showingDetails = true
        }
        .popover(isPresented: $showingDetails, arrowEdge: .trailing) {
            VersionHistoryDetailPopover(release: release, isCurrent: isCurrent)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                    if isCurrent {
                        Text("about.version_history.current_badge".localized())
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.18), in: Capsule())
                    }
                    if release.prerelease {
                        Text("about.version_history.prerelease_badge".localized())
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.16), in: Capsule())
                    }
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Link(destination: URL(string: release.htmlUrl) ?? URLConfig.API.GitHub.repositoryURL()) {
                Image(systemName: "arrow.up.right")
                    .imageScale(.small)
            }
            .buttonStyle(.borderless)
            .help("about.version_history.open_release".localized())
        }
    }

    private var displayTitle: String {
        let name = release.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? release.tagName : name
    }

    private var subtitle: String {
        var parts = [release.tagName]
        if let dateText = formattedDate(from: release.publishedAt) {
            parts.append(dateText)
        }
        if let sizeText = assetsSizeText {
            parts.append(sizeText)
        }
        return parts.joined(separator: " · ")
    }

    private var assetsSizeText: String? {
        let totalSize = release.assets.compactMap(\.size).reduce(0, +)
        guard totalSize > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
    }

    private func formattedDate(from text: String?) -> String? {
        guard let text,
              let date = ISO8601DateFormatter().date(from: text) else {
            return nil
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct VersionHistoryDetailPopover: View {
    let release: GitHubRelease
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            metadata
            Divider()
            releaseNotes
            if !release.assets.isEmpty {
                Divider()
                assets
            }
        }
        .padding(16)
        .frame(width: 420, height: 360)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.headline)
                Text(release.tagName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Link(destination: URL(string: release.htmlUrl) ?? URLConfig.API.GitHub.repositoryURL()) {
                Label("about.version_history.open_release".localized(), systemImage: "arrow.up.right")
            }
            .controlSize(.small)
        }
    }

    private var metadata: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("about.version_history.tag".localized())
                    .foregroundStyle(.secondary)
                Text(release.tagName)
                    .textSelection(.enabled)
            }
            if let publishedAt {
                GridRow {
                    Text("about.version_history.published".localized())
                        .foregroundStyle(.secondary)
                    Text(publishedAt)
                }
            }
            GridRow {
                Text("about.version_history.status".localized())
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if isCurrent {
                        statusBadge("about.version_history.current_badge".localized(), style: .tint)
                    }
                    if release.prerelease {
                        statusBadge("about.version_history.prerelease_badge".localized(), style: .secondary)
                    }
                    if !isCurrent && !release.prerelease {
                        Text("about.version_history.stable_badge".localized())
                    }
                }
            }
        }
        .font(.callout)
    }

    @ViewBuilder private var releaseNotes: some View {
        if let notes {
            ScrollView {
                MixedMarkdownView(notes)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("about.version_history.no_notes".localized())
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var assets: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("about.version_history.assets".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(release.assets, id: \.name) { asset in
                HStack {
                    Image(systemName: "shippingbox")
                        .foregroundStyle(.secondary)
                    Text(asset.name)
                        .lineLimit(1)
                    Spacer()
                    if let size = asset.size {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
        }
    }

    private var displayTitle: String {
        let name = release.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? release.tagName : name
    }

    private var notes: String? {
        let body = release.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return body.isEmpty ? nil : body
    }

    private var publishedAt: String? {
        guard let text = release.publishedAt,
              let date = ISO8601DateFormatter().date(from: text) else {
            return nil
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func statusBadge(_ text: String, style: BadgeStyle) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(style.color.opacity(0.18), in: Capsule())
    }

    private enum BadgeStyle {
        case tint
        case secondary

        var color: Color {
            switch self {
            case .tint:
                return .accentColor
            case .secondary:
                return .gray
            }
        }
    }
}
