//
//  AppModel+MangaAccess.swift
//  Mihon IOS
//

import Foundation

extension AppModel {
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
            return localContentRepository.chapters(for: manga.id, from: importRecords)
        }
        if let cached = cachedChapters(for: manga.id), !cached.isEmpty {
            return cached
        }
        return repository.chapters(for: manga.id)
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
}
