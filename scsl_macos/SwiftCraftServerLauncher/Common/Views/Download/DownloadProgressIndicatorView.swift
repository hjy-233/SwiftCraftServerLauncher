import SwiftUI

struct DownloadProgressIndicatorView: View {
    let progress: Double?

    var body: some View {
        let resolvedProgress = min(max(progress ?? 0, 0), 1)
        HStack(spacing: 8) {
            if progress == nil {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            } else {
                ProgressView(value: resolvedProgress, total: 1)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            }
            Text("\(Int(resolvedProgress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
