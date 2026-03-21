//
//  AppModel+DiagnosticsAndCache.swift
//  Mihon IOS
//

import Foundation

extension AppModel {
    func statsSections() -> [StatsSection] {
        let recentHistory = historyDisplayEntries
        let uniqueReadTitles = Set(state.history.map(\.mangaID)).count
        let latestHistory = recentHistory.first
        let latestProgress = state.progress
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
        let latestProgressTitle = latestProgress.flatMap { progress in
            allManga.first(where: { $0.id == progress.mangaID }).map { manga in
                let chapterTitle = progress.chapterTitle ?? chapter(for: progress.chapterID, in: manga)?.title ?? "Chapter"
                return StatsItem(
                    title: "Last Progress Update",
                    value: manga.title,
                    systemImage: "bookmark",
                    detail: "\(chapterTitle) • Page \(progress.pageIndex + 1) of \(max(progress.totalPages, 1))"
                )
            }
        }

        var sections: [StatsSection] = [
            StatsSection(
                title: "Overview",
                items: [
                    StatsItem(title: "Library Titles", value: "\(state.library.count)", systemImage: "books.vertical"),
                    StatsItem(title: "Titles In Progress", value: "\(state.progress.count)", systemImage: "book"),
                    StatsItem(title: "History Entries", value: "\(state.history.count)", systemImage: "clock.arrow.circlepath"),
                    StatsItem(title: "Tracked Titles", value: "\(state.trackers.count)", systemImage: "person.badge.clock"),
                    StatsItem(title: "Imported Titles", value: "\(importRecords.count)", systemImage: "tray.and.arrow.down"),
                    StatsItem(title: "Categories", value: "\(state.categories.count)", systemImage: "folder")
                ]
            ),
            StatsSection(
                title: "Reading Activity",
                items: [
                    StatsItem(title: "Titles Opened", value: "\(uniqueReadTitles)", systemImage: "text.book.closed"),
                    latestHistory.map { entry, manga, chapter in
                        StatsItem(
                            title: "Last Opened Chapter",
                            value: manga.title,
                            systemImage: "clock.badge.checkmark",
                            detail: "\(chapter.title) • \(entry.timestamp.formatted(date: .abbreviated, time: .shortened))"
                        )
                    },
                    latestProgressTitle
                ].compactMap { $0 }
            )
        ]

        let recentTitles = recentHistory.reduce(into: [StatsItem]()) { partial, item in
            guard partial.count < 3 else { return }
            let (_, manga, chapter) = item
            guard partial.contains(where: { $0.value == manga.title }) == false else { return }
            partial.append(
                StatsItem(
                    title: chapter.title,
                    value: manga.title,
                    systemImage: "clock",
                    detail: item.0.timestamp.formatted(date: .abbreviated, time: .shortened)
                )
            )
        }

        if !recentTitles.isEmpty {
            sections.append(StatsSection(title: "Recent Titles", items: recentTitles))
        }

        return sections.filter { !$0.items.isEmpty }
    }

    var hasMeaningfulStats: Bool {
        !state.library.isEmpty || !state.progress.isEmpty || !state.history.isEmpty || !state.trackers.isEmpty || !importRecords.isEmpty
    }

    func diagnosticsSummary() -> [String] {
        [
            "Schema v\(state.schemaVersion)",
            "Sources: \(visibleSources.count)/\(sources.count)",
            "Source repos: \(state.sourceRepos.count)",
            "Page cache: \(pageCache.count)",
            "Chapter cache: \(chapterCache.count)",
            "Disk image cache: \(formatBytes(cacheStats.diskImageBytes))",
            "Disk metadata cache: \(formatBytes(cacheStats.diskMetadataBytes))",
            "Cache hits/misses: \(cacheStats.hitCount)/\(cacheStats.missCount)",
            "Error logs: \(diagnosticLogs.count)",
        ]
    }

    func clearDiagnostics() {
        diagnosticLogs.removeAll()
        persist()
    }

    func clearImageCache() async {
        await ReaderImagePipeline.shared.clear()
        await refreshCacheStats()
    }

    func clearSourceMetadataCache() async {
        await cacheController.clear(.sourceMetadata)
        clearCachedGenreTags()
        clearCachedSourceManga()
        clearCachedChapters(preservingOfflineOnly: true)
        clearCachedPages()
        appendDiagnostic(kind: .cache, title: "Metadata Cache Cleared", message: "Source metadata caches were cleared.", metadata: [:])
        await refreshCacheStats()
    }

    func clearAllCaches() async {
        await cacheController.clear(.all)
        clearCachedGenreTags()
        clearCachedSourceManga()
        clearCachedChapters(preservingOfflineOnly: true)
        clearCachedPages()
        appendDiagnostic(kind: .cache, title: "All Caches Cleared", message: "Image and metadata caches were cleared.", metadata: [:])
        await refreshCacheStats()
    }

    func respondToMemoryPressure() {
        trimRuntimeCaches(fraction: 0.5)

        Task {
            await cacheController.trimMemory(fraction: 0.5)
            await refreshCacheStats()
        }

        appendDiagnostic(kind: .cache, title: "Memory Pressure Response", message: "Trimmed in-memory caches by 50%.", metadata: [
            "pageCache": "\(pageCache.count)",
            "sourceMangaCache": "\(sourceMangaCache.count)",
            "chapterCache": "\(chapterCache.count)",
        ])
    }

    private func formatBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

struct StatsItem: Identifiable, Hashable {
    var id: String { title }
    let title: String
    let value: String
    let systemImage: String
    var detail: String? = nil
}

struct StatsSection: Identifiable, Hashable {
    var id: String { title }
    let title: String
    let items: [StatsItem]
}
