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
        if downloadActiveJobID == jobID {
            downloadActiveTask?.cancel()
        }
        downloadJobs[index].state = .failed
        downloadJobs[index].errorMessage = "Cancelled"
        downloadJobs[index].progress = max(downloadJobs[index].progress, 0)

        cleanupPartialDownload(for: job)
        if downloadActiveJobID == jobID {
            downloadActiveJobID = nil
            downloadActiveTask = nil
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
        guard downloadActiveTask == nil else { return }
        guard let next = downloadJobs
            .filter({ $0.state == .queued })
            .sorted(by: { $0.queuedAt < $1.queuedAt })
            .first
        else { return }

        updateJob(next.id) { job in
            job.state = .downloading
            job.errorMessage = nil
        }

        downloadActiveJobID = next.id

        let task = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.performDownload(jobID: next.id)
        }
        downloadActiveTask = task
    }

    private func performDownload(jobID: UUID) async {
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
        try FileManager.default.createDirectory(at: chapterBase, withIntermediateDirectories: true, attributes: nil)

        let partial = chapterBase.appendingPathComponent("\(chapterComponent).partial", isDirectory: true)
        let committed = chapterBase.appendingPathComponent(chapterComponent, isDirectory: true)
        try? FileManager.default.removeItem(at: partial)
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true, attributes: nil)

        let imagePages = pages.filter { $0.assetKind == .image }
        let total = max(imagePages.count, 1)
        var completedCount = 0

        var updated: [ReaderPage] = []
        updated.reserveCapacity(pages.count)

        for page in pages {
            if Task.isCancelled { throw CancellationError() }
            if page.assetKind != .image {
                updated.append(page)
                continue
            }

            guard let remote = page.remoteURL, let url = URL(string: remote) else {
                throw NSError(domain: "Downloads", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing page URL."])
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                throw URLError(.badServerResponse)
            }

            let ext = url.pathExtension.isEmpty ? "img" : url.pathExtension
            let fileURL = partial.appendingPathComponent("page_\(page.index).\(ext)")
            try data.write(to: fileURL, options: .atomic)

            let newPage = ReaderPage(
                id: page.id,
                index: page.index,
                title: page.title,
                body: page.body,
                accentHex: page.accentHex,
                assetKind: page.assetKind,
                assetPath: fileURL.path,
                remoteURL: page.remoteURL
            )
            updated.append(newPage)

            completedCount += 1
            let progress = Double(completedCount) / Double(total)
            await MainActor.run {
                self.updateJob(job.id) { item in
                    item.progress = min(max(progress, 0), 1)
                }
            }
        }

        try FileManager.default.createDirectory(at: chapterBase, withIntermediateDirectories: true, attributes: nil)
        try? FileManager.default.removeItem(at: committed)
        try FileManager.default.moveItem(at: partial, to: committed)
        let committedPages = updated.map { page in
            guard let assetPath = page.assetPath else { return page }
            let partialPrefix = partial.path + "/"
            let finalPath: String
            if assetPath.hasPrefix(partialPrefix) {
                finalPath = committed.path + "/" + assetPath.dropFirst(partialPrefix.count)
            } else {
                finalPath = assetPath.replacingOccurrences(of: ".partial/", with: "/")
            }

            return ReaderPage(
                id: page.id,
                index: page.index,
                title: page.title,
                body: page.body,
                accentHex: page.accentHex,
                assetKind: page.assetKind,
                assetPath: finalPath,
                remoteURL: page.remoteURL
            )
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
            if self.downloadActiveJobID == jobID {
                self.downloadActiveJobID = nil
                self.downloadActiveTask = nil
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
