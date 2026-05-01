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

    init(style: ResourceCardStyle) {
        switch style {
        case .compact:
            iconSize = 36
            cornerRadius = 6
            tagCornerRadius = 5
            verticalPadding = 1
            tagHorizontalPadding = 2
            tagVerticalPadding = 1
            spacing = 2
            descriptionLineLimit = 1
            maxTags = 2
            contentSpacing = 6
        case .card:
            iconSize = 48
            cornerRadius = 8
            tagCornerRadius = 6
            verticalPadding = 3
            tagHorizontalPadding = 3
            tagVerticalPadding = 1
            spacing = 3
            descriptionLineLimit = 1
            maxTags = 3
            contentSpacing = 8
        }
    }
}
