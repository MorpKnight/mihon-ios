//
//  DownloadQueueView.swift
//  Mihon IOS
//

import SwiftUI

struct DownloadQueueView: View {
    @EnvironmentObject private var model: AppModel

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
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Download Queue")
    }
}
