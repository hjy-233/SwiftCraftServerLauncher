import SwiftUI

private enum Constants {
    static let versionPopoverMinWidth: CGFloat = 320
    static let versionPopoverMaxHeight: CGFloat = 360
    static let versionPopoverMinHeight: CGFloat = 200
}

struct CustomVersionPicker: View {
    @Binding var selected: String
    let availableVersions: [String]
    @Binding var time: String
    let onVersionSelected: (String) async -> String  // 新增：版本选择回调，返回时间信息
    @State private var showMenu = false
    @State private var error: GlobalError?
    @State private var searchText = ""

    private var versionItems: [FilterItem] {
        availableVersions.map { FilterItem(id: $0, name: $0) }
    }

    private var filteredVersionItems: [FilterItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return versionItems
        }
        return versionItems.filter { matchesFuzzy(item: $0.name, query: trimmed) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("game.form.version".localized())
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Spacer()
                Text(
                    time.isEmpty ? "" : "release.time.prefix".localized() + time
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            versionInput
        }
        .alert(
            "error.notification.validation.title".localized(),
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
    }

    private var versionInput: some View {
        ZStack {
            TextField("", text: .constant(""))
                .textFieldStyle(.roundedBorder)
                .allowsHitTesting(false)
                .focusable(false)
            HStack {
                Text(
                    selected.isEmpty
                        ? "game.form.version.placeholder".localized()
                        : selected
                )
                .foregroundColor(.primary)
                .padding(.horizontal, 6)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .onTapGesture {
            if !availableVersions.isEmpty {
                showMenu.toggle()
            } else {
                handleEmptyVersionsError()
            }
        }
        .popover(isPresented: $showMenu, arrowEdge: .trailing) {
            versionPopoverContent
        }
    }

    private var versionPopoverContent: some View {
        VStack(spacing: 10) {
            VersionGroupedView(
                items: filteredVersionItems,
                selectedItem: Binding<String?>(
                    get: { selected.isEmpty ? nil : selected },
                    set: { newValue in
                        if let newValue = newValue {
                            selected = newValue
                            showMenu = false
                            // 使用版本时间映射来设置时间信息
                            Task {
                                time = await onVersionSelected(newValue)
                            }
                        }
                    }
                )
            ) { version in
                selected = version
                showMenu = false
                // 使用版本时间映射来设置时间信息
                Task {
                    time = await onVersionSelected(version)
                }
            }

            TextField("common.search".localized(), text: $searchText)
                .textFieldStyle(.roundedBorder)
        }
        .frame(
            minWidth: Constants.versionPopoverMinWidth,
            maxWidth: Constants.versionPopoverMinWidth,
            minHeight: Constants.versionPopoverMinHeight,
            maxHeight: Constants.versionPopoverMaxHeight
        )
        .padding(.horizontal, 6)
    }

    private func handleEmptyVersionsError() {
        let globalError = GlobalError.resource(
            chineseMessage: "没有可用的版本",
            i18nKey: "error.resource.no_versions_available",
            level: .notification
        )
        Logger.shared.error("版本选择器错误: \(globalError.chineseMessage)")
        GlobalErrorHandler.shared.handle(globalError)
        error = globalError
    }

    private func handleVersionSelectionError(_ error: Error) {
        let globalError = GlobalError.from(error)
        Logger.shared.error("版本选择错误: \(globalError.chineseMessage)")
        GlobalErrorHandler.shared.handle(globalError)
        self.error = globalError
    }

    private func matchesFuzzy(item: String, query: String) -> Bool {
        if item.localizedCaseInsensitiveContains(query) {
            return true
        }
        let itemChars = Array(item.lowercased())
        let queryChars = Array(query.lowercased())
        var index = 0
        for char in queryChars {
            var found = false
            while index < itemChars.count {
                if itemChars[index] == char {
                    found = true
                    index += 1
                    break
                }
                index += 1
            }
            if !found {
                return false
            }
        }
        return true
    }
}
