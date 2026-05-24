import SwiftUI

struct ResourceCardMetrics {
    let iconSize: CGFloat
    let cornerRadius: CGFloat
    let tagCornerRadius: CGFloat
    let verticalPadding: CGFloat
    let tagHorizontalPadding: CGFloat
    let tagVerticalPadding: CGFloat
    let spacing: CGFloat
    let descriptionLineLimit: Int
    let maxTags: Int
    let contentSpacing: CGFloat
    let rowInsets: EdgeInsets
    let cardPadding: CGFloat
    let titleLineLimit: Int
    let dividerInset: CGFloat

    init(style: ResourceCardStyle) {
        switch style {
        case .compact:
            iconSize = 44
            cornerRadius = 12
            tagCornerRadius = 6
            verticalPadding = 2
            tagHorizontalPadding = 5
            tagVerticalPadding = 2
            spacing = 4
            descriptionLineLimit = 2
            maxTags = 2
            contentSpacing = 12
            rowInsets = EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)
            cardPadding = 0
            titleLineLimit = 1
            dividerInset = 100
        case .card:
            iconSize = 72
            cornerRadius = 20
            tagCornerRadius = 8
            verticalPadding = 6
            tagHorizontalPadding = 8
            tagVerticalPadding = 3
            spacing = 6
            descriptionLineLimit = 3
            maxTags = 3
            contentSpacing = 14
            rowInsets = EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18)
            cardPadding = 16
            titleLineLimit = 2
            dividerInset = 0
        }
    }
}
