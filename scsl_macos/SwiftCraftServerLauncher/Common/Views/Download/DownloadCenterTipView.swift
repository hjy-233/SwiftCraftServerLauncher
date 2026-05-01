import SwiftUI

struct DownloadCenterTipView: View {
    @ObservedObject private var downloadCenter = DownloadCenter.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("download.center".localized())
                    .font(.headline)
                Spacer()
            }

            if downloadCenter.activeTasks.isEmpty {
                Text("download.no.tasks".localized())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(downloadCenter.activeTasks) { item in
                            DownloadCenterRow(item: item)
                                .padding(.vertical, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .frame(width: 360, height: 260)
    }
}

private struct DownloadCenterRow: View {
    @ObservedObject private var downloadCenter = DownloadCenter.shared
    let item: DownloadCenter.TaskItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.iconSystemName)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.subheadline)
                    .lineLimit(1)
                if let progress = item.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                }
            }
            Spacer(minLength: 8)
            if let progress = item.progress {
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
            Button {
                downloadCenter.cancelTask(id: item.id)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.plain)
            .help("download.cancel".localized())
        }
    }
}

#Preview {
    DownloadCenterTipView()
}
