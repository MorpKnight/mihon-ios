//
//  DownloadsView.swift
//  Mihon IOS
//

import SwiftUI

private enum DownloadsSegment: String, CaseIterable, Identifiable {
    case queue = "Queue"
    case downloaded = "Downloaded"

    var id: String { rawValue }
}

struct DownloadsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var segment: DownloadsSegment = .downloaded

    var body: some View {
        VStack(spacing: 12) {
            Picker("Downloads", selection: $segment) {
                ForEach(DownloadsSegment.allCases) { segment in
                    Text(segment.rawValue).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            switch segment {
            case .queue:
                DownloadQueueView(showsNavigationTitle: false)
            case .downloaded:
                DownloadedTitlesListView()
            }
        }
        .navigationTitle("Downloads")
        .onAppear {
            if !model.downloadJobs.isEmpty {
                segment = .queue
            }
        }
    }
}

private struct DownloadedTitlesListView: View {
    @EnvironmentObject private var model: AppModel

    private struct DownloadedTitle: Identifiable, Hashable {
        var id: String { manga.id }
        let manga: Manga
        let downloadedCount: Int
        let totalCachedCount: Int
        let activeJobsCount: Int
    }

    private var items: [DownloadedTitle] {
        let persistedByID = Dictionary(uniqueKeysWithValues: model.state.persistedMangas.map { ($0.id, $0) })
        let candidates = model.chapterCache.compactMap { (mangaID, chapters) -> DownloadedTitle? in
            let downloadedCount = chapters.filter(\.isDownloaded).count
            guard downloadedCount > 0 else { return nil }
            guard let manga = persistedByID[mangaID] else { return nil }
            let activeJobsCount = model.downloadJobs.filter { $0.mangaID == mangaID && $0.sourceID == manga.sourceID && ($0.state == .queued || $0.state == .downloading || $0.state == .paused || $0.state == .failed) }.count
            return DownloadedTitle(
                manga: manga,
                downloadedCount: downloadedCount,
                totalCachedCount: chapters.count,
                activeJobsCount: activeJobsCount
            )
        }
        return candidates.sorted { $0.manga.title.localizedCaseInsensitiveCompare($1.manga.title) == .orderedAscending }
    }

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView(
                    "No downloads yet",
                    systemImage: "arrow.down.circle",
                    description: Text("Downloaded chapters will appear here even if the title isn't in your Library.")
                )
                .padding(.vertical, 12)
            } else {
                Section("Downloaded Titles") {
                    ForEach(items) { item in
                        NavigationLink {
                            MangaDetailView(manga: item.manga)
                        } label: {
                            HStack(spacing: 14) {
                                MangaCoverView(manga: item.manga)
                                    .frame(width: 54, height: 74)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.manga.title)
                                        .font(.headline)

                                    Text(downloadSubtitle(item))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
        }
    }

    private func downloadSubtitle(_ item: DownloadedTitle) -> String {
        if item.activeJobsCount > 0 {
            return "\(item.downloadedCount) downloaded • \(item.activeJobsCount) in queue"
        }
        if item.totalCachedCount > 0 {
            return "\(item.downloadedCount) downloaded"
        }
        return "\(item.downloadedCount) downloaded"
    }
}
