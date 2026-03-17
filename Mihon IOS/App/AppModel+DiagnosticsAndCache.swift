//
//  AppModel+DiagnosticsAndCache.swift
//  Mihon IOS
//

import Foundation

extension AppModel {
    func statsSummary() -> [StatsItem] {
        [
            StatsItem(title: "Library Titles", value: "\(state.library.count)", systemImage: "books.vertical"),
            StatsItem(title: "Tracked Titles", value: "\(state.trackers.count)", systemImage: "person.badge.clock"),
            StatsItem(title: "Imported Titles", value: "\(importRecords.count)", systemImage: "tray.and.arrow.down"),
            StatsItem(title: "History Entries", value: "\(state.history.count)", systemImage: "clock.arrow.circlepath"),
        ]
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
        sourceGenreCache.removeAll()
        sourceMangaCache.removeAll()
        chapterCache.removeAll()
        pageCache.removeAll()
        appendDiagnostic(kind: .cache, title: "Metadata Cache Cleared", message: "Source metadata caches were cleared.", metadata: [:])
        await refreshCacheStats()
    }

    func clearAllCaches() async {
        await cacheController.clear(.all)
        sourceGenreCache.removeAll()
        sourceMangaCache.removeAll()
        chapterCache.removeAll()
        pageCache.removeAll()
        appendDiagnostic(kind: .cache, title: "All Caches Cleared", message: "Image and metadata caches were cleared.", metadata: [:])
        await refreshCacheStats()
    }

    func respondToMemoryPressure() {
        // Trim AppModel in-memory dictionaries by keeping only the most essential entries
        let pageCacheLimit = max(pageCache.count / 2, 5)
        if pageCache.count > pageCacheLimit {
            let keysToRemove = Array(pageCache.keys.dropFirst(pageCacheLimit))
            for key in keysToRemove {
                pageCache[key] = nil
            }
        }

        let sourceMangaLimit = max(sourceMangaCache.count / 2, 3)
        if sourceMangaCache.count > sourceMangaLimit {
            let keysToRemove = Array(sourceMangaCache.keys.dropFirst(sourceMangaLimit))
            for key in keysToRemove {
                sourceMangaCache[key] = nil
            }
        }

        let chapterCacheLimit = max(chapterCache.count / 2, 5)
        if chapterCache.count > chapterCacheLimit {
            let keysToRemove = Array(chapterCache.keys.dropFirst(chapterCacheLimit))
            for key in keysToRemove {
                chapterCache[key] = nil
            }
        }

        sourceGenreCache.removeAll()

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
}

