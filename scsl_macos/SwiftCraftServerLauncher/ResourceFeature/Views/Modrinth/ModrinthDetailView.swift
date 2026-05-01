import SwiftUI

// MARK: - Main View
struct ModrinthDetailView: View {
    // MARK: - Properties
    let query: String
    @Binding var selectedVersions: [String]
    @Binding var selectedCategories: [String]
    @Binding var selectedFeatures: [String]
    @Binding var selectedResolutions: [String]
    @Binding var selectedPerformanceImpact: [String]
    @Binding var selectedProjectId: String?
    @Binding var selectedLoader: [String]
    let gameInfo: GameVersionInfo?
    @Binding var selectedItem: SidebarItem
    @Binding var gameType: Bool
    let header: AnyView?
    @Binding var scannedDetailIds: Set<String> // 已扫描资源的 detailId Set，用于快速查找
    @Binding var dataSource: DataSource

    @StateObject private var viewModel = ModrinthSearchViewModel()
    @State private var hasLoaded = false
    @Binding var searchText: String
    @State private var searchTimer: Timer?
    @State private var currentPage: Int = 1
    @State private var lastSearchParams: String = ""
    @State private var error: GlobalError?
    @EnvironmentObject private var generalSettings: GeneralSettingsManager

    init(
        query: String,
        selectedVersions: Binding<[String]>,
        selectedCategories: Binding<[String]>,
        selectedFeatures: Binding<[String]>,
        selectedResolutions: Binding<[String]>,
        selectedPerformanceImpact: Binding<[String]>,
        selectedProjectId: Binding<String?>,
        selectedLoader: Binding<[String]>,
        gameInfo: GameVersionInfo?,
        selectedItem: Binding<SidebarItem>,
        gameType: Binding<Bool>,
        header: AnyView? = nil,
        scannedDetailIds: Binding<Set<String>> = .constant([]),
        dataSource: Binding<DataSource> = .constant(.modrinth),
        searchText: Binding<String> = .constant("")
    ) {
        self.query = query
        _selectedVersions = selectedVersions
        _selectedCategories = selectedCategories
        _selectedFeatures = selectedFeatures
        _selectedResolutions = selectedResolutions
        _selectedPerformanceImpact = selectedPerformanceImpact
        _selectedProjectId = selectedProjectId
        _selectedLoader = selectedLoader
        self.gameInfo = gameInfo
        _selectedItem = selectedItem
        _gameType = gameType
        self.header = header
        _scannedDetailIds = scannedDetailIds
        _dataSource = dataSource
        _searchText = searchText
    }

    private var searchKey: String {
        [
            query,
            selectedVersions.joined(separator: ","),
            selectedCategories.joined(separator: ","),
            selectedFeatures.joined(separator: ","),
            selectedResolutions.joined(separator: ","),
            selectedPerformanceImpact.joined(separator: ","),
            selectedLoader.joined(separator: ","),
            String(gameType),
            dataSource.rawValue,
        ].joined(separator: "|")
    }

    private var hasMoreResults: Bool {
        viewModel.results.count < viewModel.totalHits
    }

    // MARK: - Body
    var body: some View {
        List {
            if let header {
                header
                    .listRowSeparator(.hidden)
            }
            listContent
            if viewModel.isLoadingMore {
                loadingMoreIndicator
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .task {
            if gameType {
                await initialLoadIfNeeded()
            }
        }
        // 当筛选条件变化时，重新搜索
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
                // 关闭详情后保留当前列表，后台刷新数据
                resetPagination()
                triggerSearch()
            }
        }
        .onChange(of: dataSource) { _, _ in
            // 清理之前的旧数据
            viewModel.clearResults()
            resetPagination()
//            searchText = ""
            lastSearchParams = ""
            error = nil
            hasLoaded = false
            triggerSearch()
        }
        .onChange(of: query) { _, _ in
            // 清理之前的旧数据
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
            // 优化：仅在搜索文本实际变化时触发防抖搜索
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

    // MARK: - Private Methods
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

    private func performSearchWithErrorHandling(
        page: Int,
        append: Bool
    ) async {
        do {
            try await performSearchThrowing(page: page, append: append)
            // 搜索完成后预加载图片
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
            // 完全重复，不请求
            return
        }

        guard !query.isEmpty else {
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
            projectType: query,
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

    // MARK: - Result List
    @ViewBuilder private var listContent: some View {
        Group {
            if let error = error {
                newErrorView(error)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
            } else if viewModel.isLoading {
                ForEach(0..<8, id: \.self) { index in
                    ModrinthDetailSkeletonCardView(seed: index)
                        .padding(.vertical, ResourceCardMetrics(style: generalSettings.resourceCardStyle).verticalPadding)
                        .listRowInsets(
                            EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
                        )
                        .listRowSeparator(.hidden)
                }
            } else if hasLoaded && viewModel.results.isEmpty {
                emptyResultView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(viewModel.results, id: \.projectId) { mod in
                    ModrinthDetailCardView(
                        project: mod,
                        selectedVersions: selectedVersions,
                        selectedLoaders: selectedLoader,
                        gameInfo: gameInfo,
                        query: query,
                        type: true,
                        selectedItem: $selectedItem,
                        scannedDetailIds: $scannedDetailIds
                    )
                    .padding(.vertical, ResourceCardMetrics(style: generalSettings.resourceCardStyle).verticalPadding)
                    .listRowInsets(
                        EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
                    )
                    .listRowSeparator(.hidden)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            selectedProjectId = mod.projectId
                            if let type = ResourceType(rawValue: query) {
                                selectedItem = .resource(type)
                            }
                        }
                    }
                    .onAppear {
                        loadNextPageIfNeeded(currentItem: mod)
                    }
                }
            }
        }
    }

    private func loadNextPageIfNeeded(currentItem mod: ModrinthProject) {
        guard hasMoreResults, !viewModel.isLoading, !viewModel.isLoadingMore else {
            return
        }
        guard
            let index = viewModel.results.firstIndex(where: { $0.projectId == mod.projectId })
        else { return }

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

    /// 后台预加载可见的资源图片（只预加载前20个）
    private func preloadImages() {
        let imageUrls = viewModel.results
            .prefix(20)  // 只预加载前 20 个可见的
            .compactMap { $0.iconUrl }
            .compactMap(URL.init(string:))

        if !imageUrls.isEmpty {
            ResourceImageCacheManager.shared.preloadImages(urls: imageUrls)
        }
    }

    private func buildSearchParamsKey(page: Int) -> String {
        [
            query,
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

    private var loadingMoreIndicator: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }
}

private struct ModrinthDetailSkeletonCardView: View {
    let seed: Int
    @EnvironmentObject private var generalSettings: GeneralSettingsManager

    private var tagCount: Int { 2 + (seed % 2) }
    private var titleWidth: CGFloat {
        SkeletonWidth.make(base: 176, variance: 34, seed: seed * 31 + 1)
    }
    private var subtitleWidth: CGFloat {
        SkeletonWidth.make(base: 238, variance: 48, seed: seed * 31 + 2)
    }

    var body: some View {
        let metrics = ResourceCardMetrics(style: generalSettings.resourceCardStyle)
        HStack(spacing: metrics.contentSpacing) {
            SkeletonView(
                width: metrics.iconSize,
                height: metrics.iconSize,
                cornerRadius: metrics.cornerRadius
            )

            VStack(alignment: .leading, spacing: metrics.spacing) {
                SkeletonView(width: titleWidth, height: 16, cornerRadius: 4)
                SkeletonView(width: subtitleWidth, height: 13, cornerRadius: 4)
                HStack(spacing: metrics.spacing) {
                    ForEach(0..<tagCount, id: \.self) { index in
                        SkeletonView(
                            width: SkeletonWidth.make(
                                base: 44,
                                variance: 10,
                                seed: seed * 31 + 10 + index
                            ),
                            height: 14,
                            cornerRadius: metrics.tagCornerRadius
                        )
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: metrics.spacing) {
                SkeletonView(
                    width: SkeletonWidth.make(base: 56, variance: 12, seed: seed * 31 + 20),
                    height: 12,
                    cornerRadius: 4
                )
                SkeletonView(
                    width: SkeletonWidth.make(base: 48, variance: 10, seed: seed * 31 + 21),
                    height: 12,
                    cornerRadius: 4
                )
                SkeletonView(
                    width: SkeletonWidth.make(base: 84, variance: 16, seed: seed * 31 + 22),
                    height: 22,
                    cornerRadius: 8
                )
            }
        }
        .frame(maxWidth: .infinity)
    }
}
