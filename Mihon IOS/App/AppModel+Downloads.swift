//
//  AppModel+Downloads.swift
//  Mihon IOS
//

import CryptoKit
import Foundation

extension AppModel {
    private func ensurePersistedMangaMetadata(_ manga: Manga) {
        if !state.persistedMangas.contains(where: { $0.id == manga.id }) {
            state.persistedMangas.append(manga)
        }
    }

    func isChapterDownloaded(manga: Manga, chapter: Chapter) -> Bool {
        guard chapter.isDownloaded else { return false }
        if chapter.pages.isEmpty {
            return true
        }
        if let any = chapter.pages.first(where: { $0.assetKind == .image && ($0.assetPath?.isEmpty == false) }) {
            return FileManager.default.fileExists(atPath: any.assetPath ?? "")
        }
        if let any = chapter.pages.first(where: { $0.assetPath?.isEmpty == false }) {
            return FileManager.default.fileExists(atPath: any.assetPath ?? "")
        }
        let folder = chapterDownloadDirectoryURL(sourceID: manga.sourceID, mangaID: manga.id, chapterID: chapter.id)
        return FileManager.default.fileExists(atPath: folder.path)
    }

    func isTitleDownloaded(manga: Manga) -> Bool {
        chapters(for: manga).contains { $0.isDownloaded }
    }

    func downloadJob(for manga: Manga, chapter: Chapter) -> DownloadJob? {
        downloadJobs.first { $0.mangaID == manga.id && $0.chapterID == chapter.id && $0.sourceID == manga.sourceID }
    }

    func enqueueDownload(manga: Manga, chapter: Chapter) {
        guard supportsLiveSource(sourceID: manga.sourceID) else { return }
        guard !chapter.isDownloaded else { return }
        guard downloadJob(for: manga, chapter: chapter) == nil else { return }

        ensurePersistedMangaMetadata(manga)

        let job = DownloadJob(
            id: UUID(),
            mangaID: manga.id,
            chapterID: chapter.id,
            sourceID: manga.sourceID,
            queuedAt: .now,
            manga: manga,
            chapter: chapter,
            progress: 0,
            state: .queued,
            errorMessage: nil
        )
        downloadJobs.append(job)
        startNextDownloadIfNeeded()
    }

    func enqueueDownloadAllChapters(manga: Manga, chapters: [Chapter]) {
        guard supportsLiveSource(sourceID: manga.sourceID) else { return }
        ensurePersistedMangaMetadata(manga)
        for chapter in chapters {
            if chapter.isDownloaded { continue }
            if downloadJob(for: manga, chapter: chapter) != nil { continue }
            let job = DownloadJob(
                id: UUID(),
                mangaID: manga.id,
                chapterID: chapter.id,
                sourceID: manga.sourceID,
                queuedAt: .now,
                manga: manga,
                chapter: chapter,
                progress: 0,
                state: .queued,
                errorMessage: nil
            )
            downloadJobs.append(job)
        }
        startNextDownloadIfNeeded()
    }

    func removeAllDownloads(manga: Manga) {
        let mangaJobs = downloadJobs.filter { $0.mangaID == manga.id && $0.sourceID == manga.sourceID }
        for job in mangaJobs {
            cancelDownload(jobID: job.id)
            downloadJobs.removeAll { $0.id == job.id }
        }

        let base = downloadsDirectoryURL
            .appendingPathComponent(safePathComponent(manga.sourceID, fallbackSeed: manga.sourceID), isDirectory: true)
            .appendingPathComponent(safePathComponent(manga.id, fallbackSeed: manga.id), isDirectory: true)
        try? FileManager.default.removeItem(at: base)

        // Cleanup legacy path.
        let legacy = downloadsDirectoryURL
            .appendingPathComponent(manga.sourceID, isDirectory: true)
            .appendingPathComponent(manga.id, isDirectory: true)
        try? FileManager.default.removeItem(at: legacy)

        if var chapters = peekCachedChapters(for: manga.id) {
            chapters = chapters.map { chapter in
                Chapter(
                    id: chapter.id,
                    mangaID: chapter.mangaID,
                    title: chapter.title,
                    number: chapter.number,
                    releaseDate: chapter.releaseDate,
                    isDownloaded: false,
                    pages: []
                )
            }
            setCachedChapters(chapters, for: manga.id)
        }
        persist()
    }

    func retryDownload(jobID: UUID) {
        guard let index = downloadJobs.firstIndex(where: { $0.id == jobID }) else { return }
        guard downloadJobs[index].state == .failed else { return }
        downloadJobs[index].state = .queued
        downloadJobs[index].progress = 0
        downloadJobs[index].errorMessage = nil
        startNextDownloadIfNeeded()
    }

    func cancelDownload(jobID: UUID) {
        guard let index = downloadJobs.firstIndex(where: { $0.id == jobID }) else { return }
        let job = downloadJobs[index]
        let wasActive = downloadQueueCoordinator.cancelIfActive(jobID: jobID)
        downloadJobs[index].state = .failed
        downloadJobs[index].errorMessage = "Cancelled"
        downloadJobs[index].progress = max(downloadJobs[index].progress, 0)

        cleanupPartialDownload(for: job)
        if wasActive {
            startNextDownloadIfNeeded()
        }
    }

    func removeDownloaded(manga: Manga, chapter: Chapter) {
        if let job = downloadJob(for: manga, chapter: chapter) {
            switch job.state {
            case .queued, .downloading, .paused:
                cancelDownload(jobID: job.id)
            case .failed, .complete:
                downloadJobs.removeAll { $0.id == job.id }
            }
        }

        let folder = chapterDownloadDirectoryURL(sourceID: manga.sourceID, mangaID: manga.id, chapterID: chapter.id)
        try? FileManager.default.removeItem(at: folder)
        // Cleanup legacy path (pre-sanitization). Guard against empty IDs to avoid deleting the whole manga folder.
        let legacyBase = downloadsDirectoryURL
            .appendingPathComponent(manga.sourceID, isDirectory: true)
            .appendingPathComponent(manga.id, isDirectory: true)
        if !chapter.id.isEmpty {
            try? FileManager.default.removeItem(at: legacyBase.appendingPathComponent(chapter.id, isDirectory: true))
        }
        try? FileManager.default.removeItem(at: legacyBase.appendingPathComponent("\(chapter.id).partial", isDirectory: true))

        if var chapters = peekCachedChapters(for: manga.id), let index = chapters.firstIndex(where: { $0.id == chapter.id }) {
            let existing = chapters[index]
            chapters[index] = Chapter(
                id: existing.id,
                mangaID: existing.mangaID,
                title: existing.title,
                number: existing.number,
                releaseDate: existing.releaseDate,
                isDownloaded: false,
                pages: []
            )
            setCachedChapters(chapters, for: manga.id)
        }

        removeCachedPages(for: chapter.id)
        pageLoadErrors[chapter.id] = nil
        persist()
    }

    private func startNextDownloadIfNeeded() {
        guard let nextID = downloadQueueCoordinator.startIfIdle(jobs: downloadJobs, run: { [weak self] jobID in
            guard let self else { return }
            await self.performDownload(jobID: jobID)
        }) else { return }

        updateJob(nextID) { job in
            job.state = .downloading
            job.errorMessage = nil
        }
    }

    private func performDownload(jobID: UUID) async {
        let backgroundTaskID = await MainActor.run {
            backgroundTaskManager.beginTask(name: "Mihon.Download.\(jobID.uuidString)") { [weak self] in
                Task { @MainActor in
                    self?.cancelDownload(jobID: jobID)
                }
            }
        }
        defer {
            Task { @MainActor in
                backgroundTaskManager.endTask(backgroundTaskID)
            }
        }

        let job = await MainActor.run { self.downloadJobs.first(where: { $0.id == jobID }) }
        guard let job else {
            await finishActiveDownload(jobID: jobID)
            return
        }

        do {
            let pages = try await resolveDownloadPages(for: job)
            let (updatedPages, committedDirectoryURL) = try await downloadAndStorePages(job: job, pages: pages)
            await MainActor.run {
                self.commitDownloadedChapter(job: job, pages: updatedPages)
                self.updateJob(jobID) { item in
                    item.progress = 1
                    item.state = .complete
                    item.errorMessage = nil
                }
                _ = committedDirectoryURL
            }
        } catch is CancellationError {
            await MainActor.run {
                self.updateJob(jobID) { item in
                    item.state = .failed
                    item.errorMessage = "Cancelled"
                }
            }
        } catch {
            await MainActor.run {
                self.updateJob(jobID) { item in
                    item.state = .failed
                    item.errorMessage = error.localizedDescription
                }
            }
        }

        await finishActiveDownload(jobID: jobID)
    }

    private func resolveDownloadPages(for job: DownloadJob) async throws -> [ReaderPage] {
        if !job.chapter.pages.isEmpty {
            return job.chapter.pages
        }
        let pages = await refreshPages(for: job.chapter, sourceID: job.sourceID)
        if pages.isEmpty {
            throw NSError(domain: "Downloads", code: 1, userInfo: [NSLocalizedDescriptionKey: "No pages available for download."])
        }
        return pages
    }

    private func downloadAndStorePages(job: DownloadJob, pages: [ReaderPage]) async throws -> ([ReaderPage], URL) {
        let base = await MainActor.run { self.downloadsDirectoryURL }
        let (sourceComponent, mangaComponent, chapterComponent) = downloadPathComponents(for: job)
        let chapterBase = base
            .appendingPathComponent(sourceComponent, isDirectory: true)
            .appendingPathComponent(mangaComponent, isDirectory: true)
        let committed = chapterBase.appendingPathComponent(chapterComponent, isDirectory: true)
        let committedPages = try await downloadsService.downloadAndStorePages(
            pages: pages,
            chapterBaseDirectory: chapterBase,
            chapterComponent: chapterComponent
        ) { progress in
            await MainActor.run {
                self.updateJob(job.id) { item in
                    item.progress = progress
                }
            }
        }
        return (committedPages, committed)
    }

    private func commitDownloadedChapter(job: DownloadJob, pages: [ReaderPage]) {
        ensurePersistedMangaMetadata(job.manga)

        let downloadedChapter = Chapter(
            id: job.chapter.id,
            mangaID: job.chapter.mangaID,
            title: job.chapter.title,
            number: job.chapter.number,
            releaseDate: job.chapter.releaseDate,
            isDownloaded: true,
            pages: pages
        )

        var chapters = peekCachedChapters(for: job.mangaID) ?? chapters(for: job.manga)
        if let index = chapters.firstIndex(where: { $0.id == downloadedChapter.id }) {
            chapters[index] = downloadedChapter
        } else {
            chapters.insert(downloadedChapter, at: 0)
        }
        setCachedChapters(chapters, for: job.mangaID)
        setCachedPages(pages, for: downloadedChapter.id)
        pageLoadErrors[downloadedChapter.id] = nil
        persist()
    }

    private func chapterDownloadDirectoryURL(sourceID: String, mangaID: String, chapterID: String) -> URL {
        let safeSource = safePathComponent(sourceID, fallbackSeed: sourceID)
        let safeManga = safePathComponent(mangaID, fallbackSeed: mangaID)
        let safeChapter = safePathComponent(chapterID, fallbackSeed: "\(sourceID)|\(mangaID)|\(chapterID)")
        return downloadsDirectoryURL
            .appendingPathComponent(safeSource, isDirectory: true)
            .appendingPathComponent(safeManga, isDirectory: true)
            .appendingPathComponent(safeChapter, isDirectory: true)
    }

    private func cleanupPartialDownload(for job: DownloadJob) {
        let (sourceComponent, mangaComponent, chapterComponent) = downloadPathComponents(for: job)
        let partial = downloadsDirectoryURL
            .appendingPathComponent(sourceComponent, isDirectory: true)
            .appendingPathComponent(mangaComponent, isDirectory: true)
            .appendingPathComponent("\(chapterComponent).partial", isDirectory: true)
        try? FileManager.default.removeItem(at: partial)

        // Cleanup legacy partial path (pre-sanitization).
        let legacyPartial = downloadsDirectoryURL
            .appendingPathComponent(job.sourceID, isDirectory: true)
            .appendingPathComponent(job.mangaID, isDirectory: true)
            .appendingPathComponent("\(job.chapterID).partial", isDirectory: true)
        try? FileManager.default.removeItem(at: legacyPartial)
    }

    private func updateJob(_ jobID: UUID, mutate: (inout DownloadJob) -> Void) {
        guard let index = downloadJobs.firstIndex(where: { $0.id == jobID }) else { return }
        var job = downloadJobs[index]
        mutate(&job)
        downloadJobs[index] = job
    }

    private func finishActiveDownload(jobID: UUID) async {
        await MainActor.run {
            if self.downloadQueueCoordinator.finishIfActive(jobID: jobID) {
                self.startNextDownloadIfNeeded()
            }
        }
    }

    private func downloadPathComponents(for job: DownloadJob) -> (String, String, String) {
        let sourceComponent = safePathComponent(job.sourceID, fallbackSeed: job.sourceID)
        let mangaComponent = safePathComponent(job.mangaID, fallbackSeed: job.mangaID)
        let chapterSeed = [
            job.sourceID,
            job.mangaID,
            job.chapterID,
            job.chapter.title,
            String(job.chapter.number),
            String(job.chapter.releaseDate.timeIntervalSince1970),
        ].joined(separator: "|")
        let chapterComponent = safePathComponent(job.chapterID, fallbackSeed: chapterSeed)
        return (sourceComponent, mangaComponent, chapterComponent)
    }

    private func safePathComponent(_ raw: String, fallbackSeed: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_."))),
           !encoded.isEmpty {
            return String(encoded.prefix(180))
        }
        return stableHash(fallbackSeed)
    }

    private func stableHash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
