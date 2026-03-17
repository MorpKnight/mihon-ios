//
//  DownloadQueueView.swift
//  Mihon IOS
//

import SwiftUI

struct DownloadQueueView: View {
    @EnvironmentObject private var model: AppModel
    var showsNavigationTitle: Bool = true

    var body: some View {
        List {
            ForEach(model.jobs()) { job in
                VStack(alignment: .leading, spacing: 8) {
                    Text(job.manga.title)
                        .font(.headline)
                    Text(job.chapter.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ProgressView(value: job.progress)
                    Text(job.state.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let message = job.errorMessage, !message.isEmpty {
                        Text(message)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 4)
                .swipeActions {
                    switch job.state {
                    case .queued, .downloading:
                        Button(role: .destructive) {
                            model.cancelDownload(jobID: job.id)
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle")
                        }
                    case .failed:
                        Button {
                            model.retryDownload(jobID: job.id)
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                        Button(role: .destructive) {
                            model.cancelDownload(jobID: job.id)
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle")
                        }
                    case .complete:
                        Button(role: .destructive) {
                            model.removeDownloaded(manga: job.manga, chapter: job.chapter)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    case .paused:
                        Button(role: .destructive) {
                            model.cancelDownload(jobID: job.id)
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle")
                        }
                    }
                }
            }
        }
        .applyIf(showsNavigationTitle) { view in
            view.navigationTitle("Download Queue")
        }
    }
}

private extension View {
    @ViewBuilder
    func applyIf<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
