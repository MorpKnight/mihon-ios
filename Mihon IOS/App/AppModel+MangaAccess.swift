//
//  AppModel+MangaAccess.swift
//  Mihon IOS
//

import Foundation

extension AppModel {
    struct ChapterOrderAnomaly {
        let mismatchCount: Int
        let originalPreview: String
        let normalizedPreview: String
    }

    var allManga: [Manga] {
        let remote = (
            repository.sources()
                .filter { $0.kind == .remote }
                .flatMap { repository.mangas(for: $0.id) } +
            sourceMangaCache.values.flatMap { $0 } +
            state.persistedMangas
        ).reduce(into: [String: Manga]()) { partialResult, manga in
            if let existing = partialResult[manga.id] {
                partialResult[manga.id] = preferredManga(existing, manga)
            } else {
                partialResult[manga.id] = manga
            }
        }
        return remote.values.sorted { $0.title < $1.title } +
        localContentRepository.mangas(from: importRecords, sourceID: "local-files")
    }

    func mangas(for source: Source) -> [Manga] {
        let items: [Manga]
        if source.kind == .local {
            items = localContentRepository.mangas(from: importRecords, sourceID: source.id)
        } else if let cached = cachedSourceManga(for: source.id), !cached.isEmpty {
            items = cached
        } else {
            items = repository.mangas(for: source.id)
        }
        guard !state.appSettings.downloadedOnly else {
            return items.filter { manga in chapters(for: manga).contains(where: \.isDownloaded) }
        }
        return items
    }

    func chapters(for manga: Manga) -> [Chapter] {
        if manga.sourceID == "local-files" {
            return normalizedChapters(localContentRepository.chapters(for: manga.id, from: importRecords))
        }
        if let cached = cachedChapters(for: manga.id), !cached.isEmpty {
            return normalizedChapters(cached)
        }
        return normalizedChapters(repository.chapters(for: manga.id))
    }

    func latestChapter(for manga: Manga) -> Chapter? {
        chapters(for: manga).first
    }

    func chapter(for id: String, in manga: Manga) -> Chapter? {
        chapters(for: manga).first { $0.id == id }
    }

    private func preferredManga(_ lhs: Manga, _ rhs: Manga) -> Manga {
        let lhsScore = mangaCompletenessScore(lhs)
        let rhsScore = mangaCompletenessScore(rhs)
        if rhsScore != lhsScore {
            return rhsScore > lhsScore ? rhs : lhs
        }
        return rhs.summary.count > lhs.summary.count ? rhs : lhs
    }

    private func mangaCompletenessScore(_ manga: Manga) -> Int {
        var score = 0
        if !manga.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 3 }
        if manga.coverURL != nil { score += 2 }
        if !manga.genres.isEmpty { score += 1 }
        if manga.author != "Unknown" { score += 1 }
        return score
    }

    func normalizedChapters(_ chapters: [Chapter]) -> [Chapter] {
        chapters.sorted(by: isChapterNewer(_:than:))
    }

    func detectChapterOrderAnomaly(in chapters: [Chapter]) -> ChapterOrderAnomaly? {
        guard chapters.count > 1 else { return nil }
        let normalized = normalizedChapters(chapters)
        let originalIDs = chapters.map(\.id)
        let normalizedIDs = normalized.map(\.id)
        guard originalIDs != normalizedIDs else { return nil }

        let mismatchCount = zip(originalIDs, normalizedIDs).reduce(into: 0) { count, pair in
            if pair.0 != pair.1 {
                count += 1
            }
        }

        let numericInversionDetected = zip(chapters, chapters.dropFirst()).contains { lhs, rhs in
            let lhsNumber = normalizedChapterNumber(lhs)
            let rhsNumber = normalizedChapterNumber(rhs)
            guard lhsNumber > 0, rhsNumber > 0 else { return false }
            return lhsNumber < rhsNumber
        }

        let suspiciousLargeJump = zip(chapters, chapters.dropFirst()).contains { lhs, rhs in
            let lhsNumber = normalizedChapterNumber(lhs)
            let rhsNumber = normalizedChapterNumber(rhs)
            guard lhsNumber > 0, rhsNumber > 0 else { return false }
            return abs(lhsNumber - rhsNumber) > 25 && lhsNumber < rhsNumber
        }

        guard mismatchCount > 0 || numericInversionDetected || suspiciousLargeJump else { return nil }

        return ChapterOrderAnomaly(
            mismatchCount: mismatchCount,
            originalPreview: previewChapterOrder(chapters),
            normalizedPreview: previewChapterOrder(normalized)
        )
    }

    private func isChapterNewer(_ lhs: Chapter, than rhs: Chapter) -> Bool {
        let lhsNumber = normalizedChapterNumber(lhs)
        let rhsNumber = normalizedChapterNumber(rhs)
        let lhsHasNumber = lhsNumber > 0
        let rhsHasNumber = rhsNumber > 0

        if lhsHasNumber && rhsHasNumber && lhsNumber != rhsNumber {
            return lhsNumber > rhsNumber
        }
        if lhsHasNumber != rhsHasNumber {
            return lhsHasNumber
        }
        if lhs.releaseDate != rhs.releaseDate {
            return lhs.releaseDate > rhs.releaseDate
        }
        if lhs.number != rhs.number {
            return lhs.number > rhs.number
        }
        let titleComparison = lhs.title.localizedStandardCompare(rhs.title)
        if titleComparison != .orderedSame {
            return titleComparison == .orderedDescending
        }
        return lhs.id > rhs.id
    }

    private func normalizedChapterNumber(_ chapter: Chapter) -> Double {
        chapter.number > 0 ? chapter.number : 0
    }

    private func previewChapterOrder(_ chapters: [Chapter], limit: Int = 6) -> String {
        chapters.prefix(limit).map { chapter in
            if chapter.number > 0 {
                return chapter.number == floor(chapter.number)
                    ? String(Int(chapter.number))
                    : String(chapter.number)
            }
            return chapter.title
        }.joined(separator: " ")
    }
}
