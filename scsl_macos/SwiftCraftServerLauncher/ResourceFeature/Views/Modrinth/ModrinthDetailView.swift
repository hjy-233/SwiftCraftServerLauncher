import AppKit
import SwiftUI

struct ModrinthDetailView: View {
    let resourceType: ResourceType
    let projectTypes: [String]
    @Binding var selectedVersions: [String]
    @Binding var selectedCategories: [String]
    @Binding var selectedFeatures: [String]
    @Binding var selectedResolutions: [String]
    @Binding var selectedPerformanceImpact: [String]
    @Binding var selectedProjectId: String?
    @Binding var selectedProjectSummary: ModrinthProject?
    @Binding var selectedLoader: [String]
    let gameInfo: GameVersionInfo?
    @Binding var selectedItem: SidebarItem
    @Binding var gameType: Bool
    let header: AnyView?
    @Binding var scannedDetailIds: Set<String>
    @Binding var dataSource: DataSource

    @StateObject private var viewModel = ModrinthSearchViewModel()
    @State private var hasLoaded = false
    @Binding var searchText: String
    @State private var searchTimer: Timer?
    @State private var currentPage: Int = 1
    @State private var lastSearchParams: String = ""
    @State private var error: GlobalError?
    @EnvironmentObject private var generalSettings: GeneralSettingsManager
    @EnvironmentObject private var detailState: ResourceDetailState

    init(
        resourceType: ResourceType,
        projectTypes: [String],
        selectedVersions: Binding<[String]>,
        selectedCategories: Binding<[String]>,
        selectedFeatures: Binding<[String]>,
        selectedResolutions: Binding<[String]>,
        selectedPerformanceImpact: Binding<[String]>,
        selectedProjectId: Binding<String?>,
        selectedProjectSummary: Binding<ModrinthProject?> = .constant(nil),
        selectedLoader: Binding<[String]>,
        gameInfo: GameVersionInfo?,
        selectedItem: Binding<SidebarItem>,
        gameType: Binding<Bool>,
        header: AnyView? = nil,
        scannedDetailIds: Binding<Set<String>> = .constant([]),
        dataSource: Binding<DataSource> = .constant(.modrinth),
        searchText: Binding<String> = .constant("")
    ) {
        self.resourceType = resourceType
        self.projectTypes = projectTypes
        _selectedVersions = selectedVersions
        _selectedCategories = selectedCategories
        _selectedFeatures = selectedFeatures
        _selectedResolutions = selectedResolutions
        _selectedPerformanceImpact = selectedPerformanceImpact
        _selectedProjectId = selectedProjectId
        _selectedProjectSummary = selectedProjectSummary
        _selectedLoader = selectedLoader
        self.gameInfo = gameInfo
        _selectedItem = selectedItem
        _gameType = gameType
        self.header = header
        _scannedDetailIds = scannedDetailIds
        _dataSource = dataSource
        _searchText = searchText
    }

    private var hasMoreResults: Bool {
        viewModel.results.count < viewModel.totalHits
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: gridSpacing, alignment: .top),
            count: 2
        )
    }

    private var gridSpacing: CGFloat {
        generalSettings.resourceCardStyle == .compact ? 14 : 18
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let header {
                    header
                }

                contentSection

                if viewModel.isLoadingMore {
                    loadingMoreIndicator
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .task {
            if gameType {
                await initialLoadIfNeeded()
            }
        }
        .onChange(of: selectedVersions) { _, _ in
            resetPagination()
            triggerSearch()
        }
        .onChange(of: selectedCategories) { _, _ in
            resetPagination()
            triggerSearch()
        }
        .onChange(of: selectedFeatures) { _, _ in
            resetPagination()
            triggerSearch()
        }
        .onChange(of: selectedResolutions) { _, _ in
            resetPagination()
            triggerSearch()
        }
        .onChange(of: selectedPerformanceImpact) { _, _ in
            resetPagination()
            triggerSearch()
        }
        .onChange(of: selectedLoader) { _, _ in
            resetPagination()
            triggerSearch()
        }
        .onChange(of: selectedProjectId) { oldValue, newValue in
            if oldValue != nil && newValue == nil {
                resetPagination()
                triggerSearch()
            }
        }
        .onChange(of: dataSource) { _, _ in
            viewModel.clearResults()
            resetPagination()
            lastSearchParams = ""
            error = nil
            hasLoaded = false
            triggerSearch()
        }
        .onChange(of: projectTypesKey) { _, _ in
            viewModel.clearResults()
            triggerSearch()
            searchText = ""
        }
        .searchable(
            text: $searchText,
            placement: .automatic,
            prompt: "search.resources".localized()
        )
        .onChange(of: searchText) { oldValue, newValue in
            if oldValue != newValue {
                resetPagination()
                debounceSearch()
            }
        }
        .alert(
            "error.notification.search.title".localized(),
            isPresented: .constant(error != nil)
        ) {
            Button("common.close".localized()) {
                error = nil
            }
        } message: {
            if let error = error {
                Text(error.chineseMessage)
            }
        }
        .onDisappear {
            searchTimer?.invalidate()
            searchTimer = nil
        }
    }

    @ViewBuilder private var contentSection: some View {
        if let error = error {
            newErrorView(error)
                .frame(maxWidth: .infinity, alignment: .center)
        } else if viewModel.isLoading {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: gridSpacing) {
                ForEach(0..<8, id: \.self) { index in
                    ModrinthDetailSkeletonCardView(seed: index)
                }
            }
        } else if hasLoaded && viewModel.results.isEmpty {
            emptyResultView()
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: gridSpacing) {
                ForEach(viewModel.results, id: \.projectId) { mod in
                    ModrinthDetailCardView(
                        project: mod,
                        selectedVersions: selectedVersions,
                        selectedLoaders: selectedLoader,
                        gameInfo: gameInfo,
                        query: mod.projectType,
                        type: true,
                        selectedItem: $selectedItem,
                        scannedDetailIds: $scannedDetailIds
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        openProject(mod)
                    }
                    .onAppear {
                        loadNextPageIfNeeded(currentItem: mod)
                    }
                }
            }
        }
    }

    private func initialLoadIfNeeded() async {
        if !hasLoaded {
            hasLoaded = true
            resetPagination()
            await performSearchWithErrorHandling(page: 1, append: false)
        }
    }

    private func triggerSearch() {
        Task {
            await performSearchWithErrorHandling(page: 1, append: false)
        }
    }

    private func debounceSearch() {
        searchTimer?.invalidate()
        searchTimer = Timer.scheduledTimer(
            withTimeInterval: 0.5,
            repeats: false
        ) { _ in
            Task {
                await performSearchWithErrorHandling(page: 1, append: false)
            }
        }
    }

    private func performSearchWithErrorHandling(page: Int, append: Bool) async {
        do {
            try await performSearchThrowing(page: page, append: append)
            preloadImages()
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("搜索失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            await MainActor.run {
                self.error = globalError
            }
        }
    }

    private func performSearchThrowing(page: Int, append: Bool) async throws {
        let params = buildSearchParamsKey(page: page)
        if params == lastSearchParams {
            return
        }

        guard !projectTypes.isEmpty else {
            throw GlobalError.validation(
                chineseMessage: "查询类型不能为空",
                i18nKey: "error.validation.query_type_empty",
                level: .notification
            )
        }

        lastSearchParams = params
        if !append {
            viewModel.beginNewSearch()
        }

        await viewModel.search(
            query: searchText,
            projectTypes: projectTypes,
            versions: selectedVersions,
            categories: selectedCategories,
            features: selectedFeatures,
            resolutions: selectedResolutions,
            performanceImpact: selectedPerformanceImpact,
            loaders: selectedLoader,
            page: page,
            append: append,
            dataSource: dataSource
        )
    }

    private func openProject(_ project: ModrinthProject) {
        withAnimation(.easeInOut(duration: 0.28)) {
            if generalSettings.serverInterfaceMode == .workspace,
               NSEvent.modifierFlags.contains(.command) {
                detailState.openResourceWorkspaceTab(
                    resourceType,
                    forceNew: true,
                    selectedProjectId: project.projectId
                )
                selectedProjectSummary = project
                return
            }

            selectedProjectSummary = project
            selectedProjectId = project.projectId
            selectedItem = .resource(resourceType)
        }
    }

    private func loadNextPageIfNeeded(currentItem mod: ModrinthProject) {
        guard hasMoreResults, !viewModel.isLoading, !viewModel.isLoadingMore else {
            return
        }

        guard let index = viewModel.results.firstIndex(where: { $0.projectId == mod.projectId }) else {
            return
        }

        let thresholdIndex = max(viewModel.results.count - 5, 0)
        if index >= thresholdIndex {
            currentPage += 1
            let nextPage = currentPage
            Task {
                await performSearchWithErrorHandling(page: nextPage, append: true)
            }
        }
    }

    private func resetPagination() {
        currentPage = 1
        lastSearchParams = ""
    }

    private func preloadImages() {
        let imageUrls = viewModel.results
            .prefix(20)
            .compactMap { $0.iconUrl }
            .compactMap(URL.init(string:))

        if !imageUrls.isEmpty {
            ResourceImageCacheManager.shared.preloadImages(urls: imageUrls)
        }
    }

    private func buildSearchParamsKey(page: Int) -> String {
        [
            resourceType.rawValue,
            projectTypesKey,
            selectedVersions.joined(separator: ","),
            selectedCategories.joined(separator: ","),
            selectedFeatures.joined(separator: ","),
            selectedResolutions.joined(separator: ","),
            selectedPerformanceImpact.joined(separator: ","),
            selectedLoader.joined(separator: ","),
            String(gameType),
            searchText,
            "page:\(page)",
            dataSource.rawValue,
        ].joined(separator: "|")
    }

    private var projectTypesKey: String {
        projectTypes.sorted().joined(separator: ",")
    }

    private var loadingMoreIndicator: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }
}

private struct ModrinthDetailSkeletonCardView: View {
    let seed: Int
    @EnvironmentObject private var generalSettings: GeneralSettingsManager

    private var metrics: ResourceCardMetrics {
        ResourceCardMetrics(style: generalSettings.resourceCardStyle)
    }

    private var tagCount: Int { 2 + (seed % 2) }
    private var titleWidth: CGFloat {
        SkeletonWidth.make(base: 156, variance: 34, seed: seed * 31 + 1)
    }
    private var subtitleWidth: CGFloat {
        SkeletonWidth.make(base: 210, variance: 40, seed: seed * 31 + 2)
    }

    var body: some View {
        GroupBox {
            VStack(
                alignment: .leading,
                spacing: generalSettings.resourceCardStyle == .compact ? 10 : 14
            ) {
                HStack(alignment: .top, spacing: metrics.contentSpacing) {
                    SkeletonView(
                        width: metrics.iconSize,
                        height: metrics.iconSize,
                        cornerRadius: metrics.cornerRadius
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonView(width: titleWidth, height: 18, cornerRadius: 6)
                        SkeletonView(width: subtitleWidth, height: 13, cornerRadius: 5)
                        if generalSettings.resourceCardStyle == .card {
                            SkeletonView(width: 180, height: 13, cornerRadius: 5)
                        }
                    }
                }

                HStack(spacing: 8) {
                    ForEach(0..<tagCount, id: \.self) { index in
                        SkeletonView(
                            width: SkeletonWidth.make(
                                base: 52,
                                variance: 12,
                                seed: seed * 31 + 20 + index
                            ),
                            height: 18,
                            cornerRadius: 9
                        )
                    }
                }

                HStack {
                    Spacer(minLength: 0)
                    SkeletonView(width: 96, height: 30, cornerRadius: 15)
                }
            }
        }
    }
}
