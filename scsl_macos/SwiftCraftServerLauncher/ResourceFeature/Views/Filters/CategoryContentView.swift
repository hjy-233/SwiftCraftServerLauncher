import SwiftUI

// MARK: - CategoryContent
struct CategoryContentView: View {
    // MARK: - Properties
    let project: String
    @StateObject private var viewModel: CategoryContentViewModel
    @Binding var selectedCategories: [String]
    @Binding var selectedFeatures: [String]
    @Binding var selectedResolutions: [String]
    @Binding var selectedPerformanceImpacts: [String]
    @Binding var selectedVersions: [String]
    @Binding var selectedLoaders: [String]
    @Binding var browseScope: ResourceBrowseScope
    let type: String
    let gameVersion: String?
    let gameLoader: String?
    let showsBrowseScopePicker: Bool
    let dataSource: DataSource
    @AppStorage("resource.mod.notice.hidden")
    private var hideModClientNotice = false
    @State private var showModClientNotice = true
    @State private var isVersionExpanded = true
    @State private var isCategoryExpanded = true
    @State private var isLoaderExpanded = true
    @State private var isEnvironmentExpanded = true
    @State private var isBehaviorExpanded = true
    @State private var isResolutionExpanded = true
    @State private var isPerformanceExpanded = true

    // MARK: - Initialization
    init(
        project: String,
        type: String,
        selectedCategories: Binding<[String]>,
        selectedFeatures: Binding<[String]>,
        selectedResolutions: Binding<[String]>,
        selectedPerformanceImpacts: Binding<[String]>,
        selectedVersions: Binding<[String]>,
        selectedLoaders: Binding<[String]>,
        browseScope: Binding<ResourceBrowseScope> = .constant(.all),
        gameVersion: String? = nil,
        gameLoader: String? = nil,
        showsBrowseScopePicker: Bool = false,
        dataSource: DataSource
    ) {
        self.project = project
        self.type = type
        self._selectedCategories = selectedCategories
        self._selectedFeatures = selectedFeatures
        self._selectedResolutions = selectedResolutions
        self._selectedPerformanceImpacts = selectedPerformanceImpacts
        self._selectedVersions = selectedVersions
        self._selectedLoaders = selectedLoaders
        self._browseScope = browseScope
        self.gameVersion = gameVersion
        self.gameLoader = gameLoader
        self.showsBrowseScopePicker = showsBrowseScopePicker
        self.dataSource = dataSource
        self._viewModel = StateObject(
            wrappedValue: CategoryContentViewModel(project: project)
        )
    }

    // MARK: - Body
    var body: some View {
        Group {
            if let error = viewModel.error {
                newErrorView(error)
            } else {
                if showsBrowseScopePicker {
                    Section {
                        browseScopePicker
                    }
                }
                if shouldShowModNotice {
                    Section {
                        modClientNotice
                    }
                }
                primaryFilterGroup()
                secondaryFilterGroup()
                advancedFilterGroup()
            }
        }
        .task {
            await loadDataWithErrorHandling()
            setupDefaultSelections()
        }
    }

    // MARK: - Setup Methods
    private func setupDefaultSelections() {
        if let gameVersion = gameVersion {
            selectedVersions = [gameVersion]
        }
        if let gameLoader = gameLoader {
            if project != "shader" {
                selectedLoaders = [gameLoader]
            } else {
                selectedLoaders = []
            }
        }
        if type == "resource" && project == ProjectType.mod {
            selectedFeatures = []
        }
    }

    // MARK: - Error Handling
    private func loadDataWithErrorHandling() async {
        do {
            try await loadDataThrowing()
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("加载分类数据失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            await MainActor.run {
                viewModel.setError(globalError)
            }
        }
    }

    private func loadDataThrowing() async throws {
        guard !project.isEmpty else {
            throw GlobalError.validation(
                chineseMessage: "项目类型不能为空",
                i18nKey: "error.validation.project_type_empty",
                level: .notification
            )
        }

        await viewModel.loadData()
    }

    // MARK: - Section Views
    private var categorySection: some View {
        CategorySectionView(
            title: "",
            items: viewModel.categories.map {
                FilterItem(id: $0.name, name: $0.name)
            },
            selectedItems: $selectedCategories,
            isLoading: viewModel.isLoading
        )
    }

    private var versionSection: some View {
        CategorySectionView(
            title: "",
            items: viewModel.versions.map {
                FilterItem(id: $0.id, name: $0.id)
            },
            selectedItems: $selectedVersions,
            isLoading: viewModel.isLoading,
            isVersionSection: true
        )
    }

    private var loaderSection: some View {
        FilterMenuSection(
            title: "",
            items: filteredLoaders.map {
                FilterItem(id: $0.name, name: $0.name)
            },
            selectedItems: $selectedLoaders,
            isLoading: viewModel.isLoading
        )
    }

    @ViewBuilder
    private func primaryFilterGroup() -> some View {
        if type == "resource" {
            FilterDisclosureSection(
                title: "filter.version".localized(),
                systemImage: "tag",
                isExpanded: $isVersionExpanded,
                trailingAccessory: AnyView(
                    CategorySectionOverflowButton(
                        items: viewModel.versions.map {
                            FilterItem(id: $0.id, name: $0.id)
                        },
                        selectedItems: $selectedVersions,
                        isVersionSection: true
                    )
                )
            ) {
                versionSection
            }

            FilterDisclosureSection(
                title: "filter.category".localized(),
                systemImage: "square.grid.2x2",
                isExpanded: $isCategoryExpanded,
                trailingAccessory: AnyView(
                    CategorySectionOverflowButton(
                        items: viewModel.categories.map {
                            FilterItem(id: $0.name, name: $0.name)
                        },
                        selectedItems: $selectedCategories
                    )
                )
            ) {
                categorySection
            }
        }
    }

    @ViewBuilder
    private func secondaryFilterGroup() -> some View {
        switch project {
        case ProjectType.modpack, ProjectType.mod:
            if type == "resource" {
                FilterDisclosureSection(
                    title: "filter.loader".localized(),
                    systemImage: "shippingbox",
                    isExpanded: $isLoaderExpanded
                ) {
                    loaderSection
                }
                FilterDisclosureSection(
                    title: "filter.environment.detail".localized(),
                    systemImage: "checkmark.shield",
                    isExpanded: $isEnvironmentExpanded
                ) {
                    environmentSection
                }
            }
        case ProjectType.shader:
            FilterDisclosureSection(
                title: "filter.loader".localized(),
                systemImage: "shippingbox",
                isExpanded: $isLoaderExpanded
            ) {
                loaderSection
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func advancedFilterGroup() -> some View {
        switch project {
        case ProjectType.resourcepack:
            FilterDisclosureSection(
                title: "filter.behavior".localized(),
                systemImage: "slider.horizontal.3",
                isExpanded: $isBehaviorExpanded,
                trailingAccessory: AnyView(
                    CategorySectionOverflowButton(
                        items: viewModel.features.map {
                            FilterItem(id: $0.name, name: $0.name)
                        },
                        selectedItems: $selectedFeatures
                    )
                )
            ) {
                behaviorSection
            }
            FilterDisclosureSection(
                title: "filter.resolutions".localized(),
                systemImage: "rectangle.inset.filled",
                isExpanded: $isResolutionExpanded,
                trailingAccessory: AnyView(
                    CategorySectionOverflowButton(
                        items: viewModel.resolutions.map {
                            FilterItem(id: $0.name, name: $0.name)
                        },
                        selectedItems: $selectedResolutions
                    )
                )
            ) {
                resolutionSection
            }
        case ProjectType.shader:
            FilterDisclosureSection(
                title: "filter.behavior".localized(),
                systemImage: "sparkles",
                isExpanded: $isBehaviorExpanded,
                trailingAccessory: AnyView(
                    CategorySectionOverflowButton(
                        items: viewModel.features.map {
                            FilterItem(id: $0.name, name: $0.name)
                        },
                        selectedItems: $selectedFeatures
                    )
                )
            ) {
                behaviorSection
            }
            FilterDisclosureSection(
                title: "filter.performance".localized(),
                systemImage: "speedometer",
                isExpanded: $isPerformanceExpanded,
                trailingAccessory: AnyView(
                    CategorySectionOverflowButton(
                        items: viewModel.performanceImpacts.map {
                            FilterItem(id: $0.name, name: $0.name)
                        },
                        selectedItems: $selectedPerformanceImpacts
                    )
                )
            ) {
                performanceSection
            }
        default:
            EmptyView()
        }
    }

    private var environmentSection: some View {
        EnvironmentPickerSection(
            selectedItems: $selectedFeatures,
            isLoading: viewModel.isLoading
        )
    }

    private var behaviorSection: some View {
        CategorySectionView(
            title: "",
            items: viewModel.features.map {
                FilterItem(id: $0.name, name: $0.name)
            },
            selectedItems: $selectedFeatures,
            isLoading: viewModel.isLoading
        )
    }

    private var resolutionSection: some View {
        CategorySectionView(
            title: "",
            items: viewModel.resolutions.map {
                FilterItem(id: $0.name, name: $0.name)
            },
            selectedItems: $selectedResolutions,
            isLoading: viewModel.isLoading
        )
    }

    private var performanceSection: some View {
        CategorySectionView(
            title: "",
            items: viewModel.performanceImpacts.map {
                FilterItem(id: $0.name, name: $0.name)
            },
            selectedItems: $selectedPerformanceImpacts,
            isLoading: viewModel.isLoading
        )
    }

    // MARK: - Computed Properties
    private var filteredLoaders: [Loader] {
        viewModel.loaders.filter {
            $0.supported_project_types.contains(project)
        }
    }

    private var shouldShowModNotice: Bool {
        type == "resource" && project == ProjectType.mod && !hideModClientNotice && showModClientNotice
    }

    private var browseScopePicker: some View {
        Picker("common.browse".localized(), selection: $browseScope) {
            ForEach(ResourceBrowseScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var modClientNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("resource.mod.notice".localized())
                .foregroundStyle(.primary)
                .font(.subheadline)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Button("common.confirm".localized()) {
                    showModClientNotice = false
                }
                .buttonStyle(.bordered)
                Button("resource.mod.notice.dont_show".localized()) {
                    hideModClientNotice = true
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
        )
        .padding(.bottom, 8)
    }
}

private struct FilterDisclosureSection<Content: View>: View {
    let title: String
    let systemImage: String
    @Binding var isExpanded: Bool
    let trailingAccessory: AnyView?
    let content: Content

    init(
        title: String,
        systemImage: String,
        isExpanded: Binding<Bool>,
        trailingAccessory: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self._isExpanded = isExpanded
        self.trailingAccessory = trailingAccessory
        self.content = content()
    }

    var body: some View {
        Section {
            DisclosureGroup(
                isExpanded: $isExpanded,
                content: {
                    VStack(alignment: .leading, spacing: 14) {
                        content
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                },
                label: {
                    HStack(spacing: 8) {
                        Label(title, systemImage: systemImage)
                            .font(.headline)
                        Spacer(minLength: 8)
                        if let trailingAccessory {
                            trailingAccessory
                        }
                    }
                }
            )
        }
    }
}

private struct CategorySectionOverflowButton: View {
    let items: [FilterItem]
    @Binding var selectedItems: [String]
    var isVersionSection: Bool = false

    @State private var showOverflowPopover = false

    private var overflowItems: [FilterItem] {
        items.computeVisibleAndOverflowItemsByRows(
            maxRows: SectionViewConstants.defaultMaxRows,
            maxWidth: SectionViewConstants.defaultMaxWidth
        ) { item in
            CGFloat(item.name.count) * SectionViewConstants.defaultEstimatedCharWidth
                + SectionViewConstants.defaultChipPadding
        }.1
    }

    var body: some View {
        if !overflowItems.isEmpty {
            OverflowButton(
                count: overflowItems.count,
                isPresented: $showOverflowPopover
            ) {
                overflowPopoverContent
            }
        }
    }

    @ViewBuilder private var overflowPopoverContent: some View {
        if isVersionSection {
            VersionGroupedView(
                items: items,
                selectedItems: $selectedItems
            ) { itemId in
                toggleSelection(for: itemId)
            }
            .frame(maxHeight: SectionViewConstants.defaultPopoverMaxHeight)
            .frame(width: SectionViewConstants.defaultPopoverWidth)
        } else {
            OverflowPopoverContent(
                items: overflowItems,
                maxHeight: SectionViewConstants.defaultPopoverMaxHeight,
                width: SectionViewConstants.defaultPopoverWidth
            ) { item in
                FilterChip(
                    title: item.name,
                    isSelected: selectedItems.contains(item.id)
                ) { toggleSelection(for: item.id) }
            }
        }
    }

    private func toggleSelection(for id: String) {
        if selectedItems.contains(id) {
            selectedItems.removeAll { $0 == id }
        } else {
            selectedItems.append(id)
        }
    }
}

private struct FilterMenuSection: View {
    let title: String
    let items: [FilterItem]
    @Binding var selectedItems: [String]
    let isLoading: Bool

    private var selectedTitle: String {
        if selectedItems.isEmpty {
            return "command.palette.root".localized()
        }
        let selectedNames = items
            .filter { selectedItems.contains($0.id) }
            .map(\.name)
        return selectedNames.prefix(2).joined(separator: ", ")
            + (selectedNames.count > 2 ? " +\(selectedNames.count - 2)" : "")
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Menu(selectedTitle) {
                    Button("command.palette.root".localized()) {
                        selectedItems.removeAll()
                    }
                    Divider()
                    ForEach(items) { item in
                        Button {
                            toggleSelection(for: item.id)
                        } label: {
                            if selectedItems.contains(item.id) {
                                Label(item.name, systemImage: "checkmark")
                            } else {
                                Text(item.name)
                            }
                        }
                    }
                }
                .menuStyle(.button)
            }
        }
    }

    private func toggleSelection(for id: String) {
        if selectedItems.contains(id) {
            selectedItems.removeAll { $0 == id }
        } else {
            selectedItems.append(id)
        }
    }
}

private struct EnvironmentPickerSection: View {
    @Binding var selectedItems: [String]
    let isLoading: Bool

    private enum EnvironmentSelection: String, CaseIterable, Identifiable {
        case all
        case client
        case server

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:
                return "command.palette.root".localized()
            case .client:
                return "environment.client".localized()
            case .server:
                return "environment.server".localized()
            }
        }

        var filterValue: String? {
            switch self {
            case .all:
                return nil
            case .client:
                return AppConstants.EnvironmentTypes.client
            case .server:
                return AppConstants.EnvironmentTypes.server
            }
        }
    }

    private var selection: Binding<EnvironmentSelection> {
        Binding {
            if selectedItems.contains(AppConstants.EnvironmentTypes.client) {
                return .client
            }
            if selectedItems.contains(AppConstants.EnvironmentTypes.server) {
                return .server
            }
            return .all
        } set: { newValue in
            if let filterValue = newValue.filterValue {
                selectedItems = [filterValue]
            } else {
                selectedItems.removeAll()
            }
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Picker("filter.environment.detail".localized(), selection: selection) {
                    ForEach(EnvironmentSelection.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }
}
