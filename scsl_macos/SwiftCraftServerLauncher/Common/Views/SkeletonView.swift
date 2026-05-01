import SwiftUI

struct SkeletonView: View {
    let width: CGFloat?
    let height: CGFloat
    var cornerRadius: CGFloat = 8

    @State private var shimmerPhase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.gray.opacity(0.24))
            .overlay {
                GeometryReader { proxy in
                    let shimmerWidth = max(proxy.size.width * 0.62, 30)
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.88),
                            Color.white.opacity(0.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: shimmerWidth)
                    .rotationEffect(.degrees(18))
                    .offset(x: shimmerOffsetX(containerWidth: proxy.size.width, shimmerWidth: shimmerWidth))
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .frame(maxWidth: width == nil ? .infinity : nil)
            .frame(width: width, height: height, alignment: .leading)
            .onAppear {
                shimmerPhase = -1
                withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                    shimmerPhase = 1.2
                }
            }
            .accessibilityHidden(true)
    }

    private func shimmerOffsetX(containerWidth: CGFloat, shimmerWidth: CGFloat) -> CGFloat {
        shimmerPhase * (containerWidth + shimmerWidth * 2) - shimmerWidth * 2
    }
}
