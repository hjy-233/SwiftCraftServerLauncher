import SwiftUI

/// 通用Sheet视图组件
/// 分为头部、主体、底部三个部分，自适应内容大小
struct CommonSheetView<Header: View, BodyContent: View, Footer: View>: View {

    // MARK: - Properties
    let header: Header
    let bodyContent: BodyContent
    let footer: Footer

    // MARK: - Initialization
    init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder body: () -> BodyContent,
        @ViewBuilder footer: () -> Footer
    ) {
        self.header = header()
        self.bodyContent = body()
        self.footer = footer()
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // 头部区域
            header
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            Divider()

            // 主体区域
            bodyContent
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            // 底部区域
            Divider()
            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: 720)
    }
}

// MARK: - Convenience Initializers
extension CommonSheetView where Header == EmptyView, Footer == EmptyView {
    /// 只有主体内容的初始化方法
    init(
        @ViewBuilder body: () -> BodyContent
    ) {
        self.header = EmptyView()
        self.bodyContent = body()
        self.footer = EmptyView()
    }
}

extension CommonSheetView where Footer == EmptyView {
    /// 有头部和主体的初始化方法
    init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder body: () -> BodyContent
    ) {
        self.header = header()
        self.bodyContent = body()
        self.footer = EmptyView()
    }
}

extension CommonSheetView where Header == EmptyView {
    /// 有主体和底部的初始化方法
    init(
        @ViewBuilder body: () -> BodyContent,
        @ViewBuilder footer: () -> Footer
    ) {
        self.header = EmptyView()
        self.bodyContent = body()
        self.footer = footer()
    }
}
