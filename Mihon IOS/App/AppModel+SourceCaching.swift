//
//  AppModel+SourceCaching.swift
//  Mihon IOS
//

import Foundation

extension AppModel {
    static let defaultSourceMangaCacheEntries = 30
    static let defaultSourceGenreCacheEntries = 12
    static let defaultChapterCacheEntries = 50
    static let defaultPageCacheEntries = 40

    func sourceError(for sourceID: String) -> String? {
        sourceErrors[sourceID]
    }

    func pageLoadError(for chapterID: String) -> String? {
        pageLoadErrors[chapterID]
    }

    func genreTags(for sourceID: String) -> [GenreTag] {
        cachedGenreTags(for: sourceID) ?? []
    }

    func resolvedChapter(_ chapter: Chapter) -> Chapter {
        guard let pages = cachedPages(for: chapter.id), !pages.isEmpty else { return chapter }
        return Chapter(
            id: chapter.id,
            mangaID: chapter.mangaID,
            title: chapter.title,
            number: chapter.number,
            releaseDate: chapter.releaseDate,
            isDownloaded: chapter.isDownloaded,
            pages: pages
        )
    }

    func refreshSourceFeed(for source: Source, mode: SourceFeedKind, query: String = "", filters: [SourceFilterValue] = []) async {
        guard supportsLiveSource(source) else { return }
        appendDiagnostic(kind: .stateTransition, severity: .info, title: "Source Feed Started", message: "Refreshing \(mode.rawValue) feed.", module: "SourceCaching", metadata: ["source": source.name, "mode": mode.rawValue])
        do {
            let items: [Manga]
            switch mode {
            case .popular:
                items = try await repository.popularManga(sourceID: source.id)
            case .latest:
                items = try await repository.latestManga(sourceID: source.id)
            case .search:
                items = try await repository.searchManga(sourceID: source.id, query: query, filters: filters)
            }
            setCachedSourceManga(items, for: source.id)
            sourceErrors[source.id] = nil
            appendDiagnostic(kind: .cache, severity: .info, title: "Source Feed Cached", message: "Stored \(items.count) items.", module: "SourceCaching", metadata: ["source": source.name, "mode": mode.rawValue])
            trimSourceCachesIfNeeded()
            await refreshCacheStats()
        } catch {
            sourceErrors[source.id] = error.localizedDescription
            appendDiagnostic(kind: .source, severity: .error, title: "Source Feed Failed", message: error.localizedDescription, errorCode: DiagnosticErrorCode.srcFeedFailed.rawValue, module: "SourceCaching", resolutionHint: "Check network connectivity and retry the source feed.", metadata: ["source": source.name, "mode": mode.rawValue])
        }
    }

    func loadGenreTags(for source: Source) async {
        guard supportsLiveSource(source), cachedGenreTags(for: source.id) == nil else { return }
        do {
            let genres = try await repository.genreTags(sourceID: source.id)
            setCachedGenreTags(genres, for: source.id)
            appendDiagnostic(kind: .cache, severity: .info, title: "Genre Cache Filled", message: "Loaded \(genres.count) genres.", module: "SourceCaching", metadata: ["source": source.name])
            await refreshCacheStats()
        } catch {
            sourceErrors[source.id] = error.localizedDescription
            appendDiagnostic(kind: .source, severity: .error, title: "Genre Load Failed", message: error.localizedDescription, errorCode: DiagnosticErrorCode.srcGenreLoadFailed.rawValue, module: "SourceCaching", metadata: ["source": source.name])
        }
    }

    func refreshMangaDetails(for manga: Manga) async -> Manga {
        guard supportsLiveSource(sourceID: manga.sourceID) else {
            return manga
        }
        appendDiagnostic(kind: .stateTransition, severity: .info, title: "Manga Detail Started", message: "Refreshing manga details.", module: "SourceCaching", metadata: ["manga": manga.title, "sourceID": manga.sourceID])
        do {
            let details = try await repository.mangaDetails(sourceID: manga.sourceID, mangaIDOrURL: manga.id)
            replaceCachedManga(details.manga, for: manga.sourceID)
            sourceErrors[manga.sourceID] = nil
            await refreshCacheStats()
            return details.manga
        } catch {
            sourceErrors[manga.sourceID] = error.localizedDescription
            appendDiagnostic(kind: .source, severity: .error, title: "Manga Detail Failed", message: error.localizedDescription, errorCode: DiagnosticErrorCode.srcMangaDetailFailed.rawValue, module: "SourceCaching", metadata: ["sourceID": manga.sourceID, "manga": manga.title])
            return manga
        }
    }

    func refreshChapters(for manga: Manga) async -> [Chapter] {
        if manga.sourceID == "local-files" {
            return chapters(for: manga)
        }
        appendDiagnostic(kind: .stateTransition, severity: .info, title: "Chapter Load Started", message: "Refreshing chapter list.", module: "SourceCaching", metadata: ["manga": manga.title, "sourceID": manga.sourceID])
        do {
            let details = try await repository.chapters(sourceID: manga.sourceID, manga: manga)
            if let anomaly = detectChapterOrderAnomaly(in: details.chapters) {
                appendDiagnostic(
                    kind: .source,
                    severity: .warning,
                    title: "Chapter Order Normalized",
                    message: "Detected anomalous chapter ordering from the source and normalized it by chapter number.",
                    errorCode: DiagnosticErrorCode.srcChapterOrderNormalized.rawValue,
                    module: "SourceCaching",
                    metadata: [
                        "mangaID": manga.id,
                        "mangaTitle": manga.title,
                        "sourceID": manga.sourceID,
                        "mismatchCount": "\(anomaly.mismatchCount)",
                        "originalOrder": anomaly.originalPreview,
                        "normalizedOrder": anomaly.normalizedPreview
                    ]
                )
            }
            let merged = normalizedChapters(
                mergeDownloadedChapters(existing: peekCachedChapters(for: manga.id) ?? [], incoming: details.chapters)
            )
            setCachedChapters(merged, for: manga.id)
            sourceErrors[manga.sourceID] = nil
            trimSourceCachesIfNeeded()
            await refreshCacheStats()
            return merged
        } catch {
            sourceErrors[manga.sourceID] = error.localizedDescription
            appendDiagnostic(kind: .source, severity: .error, title: "Chapter Load Failed", message: error.localizedDescription, errorCode: DiagnosticErrorCode.srcChapterLoadFailed.rawValue, module: "SourceCaching", metadata: ["sourceID": manga.sourceID, "manga": manga.title])
            return chapters(for: manga)
        }
    }

    func refreshPages(for chapter: Chapter, sourceID: String) async -> [ReaderPage] {
        guard chapter.pages.isEmpty else {
            setCachedPages(chapter.pages, for: chapter.id)
            pageLoadErrors[chapter.id] = nil
            return chapter.pages
        }
        appendDiagnostic(kind: .stateTransition, severity: .info, title: "Page Load Started", message: "Refreshing chapter pages.", module: "SourceCaching", metadata: ["sourceID": sourceID, "chapterID": chapter.id])
        do {
            let details = try await repository.pages(sourceID: sourceID, chapter: chapter)
            setCachedPages(details.pages, for: chapter.id)
            pageLoadErrors[chapter.id] = details.errorMessage
            sourceErrors[sourceID] = nil
            if let warning = details.errorMessage, !warning.isEmpty {
                appendDiagnostic(kind: .reader, severity: .warning, title: "Page Load Warning", message: warning, errorCode: DiagnosticErrorCode.rdrPageLoadWarning.rawValue, module: "SourceCaching", metadata: ["sourceID": sourceID, "chapterID": chapter.id])
            }
            trimSourceCachesIfNeeded()
            await refreshCacheStats()
            return details.pages
        } catch {
            sourceErrors[sourceID] = error.localizedDescription
            pageLoadErrors[chapter.id] = error.localizedDescription
            appendDiagnostic(kind: .reader, severity: .error, title: "Page Load Failed", message: error.localizedDescription, errorCode: DiagnosticErrorCode.rdrPageLoadFailed.rawValue, module: "SourceCaching", metadata: ["sourceID": sourceID, "chapterID": chapter.id])
            return cachedPages(for: chapter.id) ?? []
        }
    }

    func retryPages(for chapter: Chapter, sourceID: String) async -> [ReaderPage] {
        removeCachedPages(for: chapter.id)
        pageLoadErrors[chapter.id] = nil
        return await refreshPages(for: chapter, sourceID: sourceID)
    }

    private func replaceCachedManga(_ manga: Manga, for sourceID: String) {
        var items = cachedSourceManga(for: sourceID) ?? []
        if let index = items.firstIndex(where: { $0.id == manga.id || $0.title == manga.title }) {
            items[index] = manga
        } else {
            items.insert(manga, at: 0)
        }
        setCachedSourceManga(items, for: sourceID)
    }

    private func mergeDownloadedChapters(existing: [Chapter], incoming: [Chapter]) -> [Chapter] {
        guard !existing.isEmpty else { return normalizedChapters(incoming) }
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let merged = incoming.map { chapter in
            guard let cached = existingByID[chapter.id], cached.isDownloaded || !cached.pages.isEmpty else {
                return chapter
            }
            return Chapter(
                id: chapter.id,
                mangaID: chapter.mangaID,
                title: chapter.title,
                number: chapter.number,
                releaseDate: chapter.releaseDate,
                isDownloaded: cached.isDownloaded,
                pages: cached.pages.isEmpty ? chapter.pages : cached.pages
            )
        }
        return normalizedChapters(merged)
    }

    func trimSourceCachesIfNeeded() {
        // Runtime cache stores enforce their own LRU limits on insertion.
    }
}
