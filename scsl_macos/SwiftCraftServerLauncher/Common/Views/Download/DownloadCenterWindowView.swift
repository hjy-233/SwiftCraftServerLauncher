import SwiftUI

struct DownloadCenterWindowView: View {
    @StateObject private var downloadCenter = DownloadCenter.shared

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
                List(downloadCenter.activeTasks) { item in
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
                        Spacer()
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
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 320)
    }
}

#Preview {
    DownloadCenterWindowView()
}
