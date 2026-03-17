//
//  AppModel+ReaderProgress.swift
//  Mihon IOS
//

import Foundation

extension AppModel {
    func progress(for manga: Manga) -> ReadingProgress? {
        state.progress.first { $0.mangaID == manga.id }
    }

    var historyDisplayEntries: [(HistoryEntry, Manga, Chapter)] {
        state.history
            .sorted { $0.timestamp > $1.timestamp }
            .compactMap { entry in
                guard
                    let manga = allManga.first(where: { $0.id == entry.mangaID }),
                    let chapter = chapters(for: manga).first(where: { $0.id == entry.chapterID })
                else { return nil }
                return (entry, manga, chapter)
            }
    }

    func historyEntries(searchText: String) -> [(HistoryEntry, Manga, Chapter)] {
        historyDisplayEntries.filter {
            searchText.isEmpty || $0.1.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    func clearHistory() {
        state.history.removeAll()
        persist()
    }

    func clearProgress() {
        state.progress.removeAll()
        persist()
    }

    func clearNotes() {
        state.mangaNotes.removeAll()
        persist()
    }

    func removeHistoryEntry(_ entryID: UUID) {
        state.history.removeAll { $0.id == entryID }
        persist()
    }

    var updateFeed: [UpdateFeedItem] {
        libraryItems(selectedCategoryID: nil)
            .compactMap { item in
                guard let chapter = item.latestChapter else { return nil }
                let entry = UpdateEntry(
                    id: "\(item.manga.id)-\(chapter.id)",
                    mangaID: item.manga.id,
                    chapterID: chapter.id,
                    sourceID: item.manga.sourceID,
                    isBookmarked: trackerBindings(for: item.manga).isEmpty == false
                )
                return UpdateFeedItem(id: entry.id, manga: item.manga, chapter: chapter, entry: entry)
            }
            .sorted { $0.chapter.releaseDate > $1.chapter.releaseDate }
    }

    func updateFeed(searchText: String, downloadedOnly: Bool) -> [UpdateFeedItem] {
        updateFeed.filter { item in
            (!downloadedOnly || item.chapter.isDownloaded) &&
            (searchText.isEmpty || item.manga.title.localizedCaseInsensitiveContains(searchText))
        }
    }

    func startChapter(for manga: Manga) -> Chapter? {
        if let progress = progress(for: manga), let chapter = chapter(for: progress.chapterID, in: manga) {
            return chapter
        }
        return latestChapter(for: manga)
    }

    func nextChapter(after chapter: Chapter, in manga: Manga) -> Chapter? {
        let items = chapters(for: manga)
        guard let index = items.firstIndex(where: { $0.id == chapter.id }), index + 1 < items.count else { return nil }
        return items[index + 1]
    }

    func previousChapter(before chapter: Chapter, in manga: Manga) -> Chapter? {
        let items = chapters(for: manga)
        guard let index = items.firstIndex(where: { $0.id == chapter.id }), index > 0 else { return nil }
        return items[index - 1]
    }

    func updateProgress(for manga: Manga, chapter: Chapter, pageIndex: Int) {
        let boundedPage = min(max(pageIndex, 0), max(chapter.pages.count - 1, 0))
        let record = ReadingProgress(
            mangaID: manga.id,
            chapterID: chapter.id,
            pageIndex: boundedPage,
            totalPages: chapter.pages.count,
            updatedAt: .now
        )

        if let index = state.progress.firstIndex(where: { $0.mangaID == manga.id }) {
            state.progress[index] = record
        } else {
            state.progress.append(record)
        }

        if !state.appSettings.incognitoMode {
            let existingID = state.history.first(where: { $0.mangaID == manga.id && $0.chapterID == chapter.id })?.id ?? UUID()
            state.history.removeAll { $0.mangaID == manga.id && $0.chapterID == chapter.id }
            state.history.insert(
                HistoryEntry(id: existingID, mangaID: manga.id, chapterID: chapter.id, pageIndex: boundedPage, timestamp: .now),
                at: 0
            )
            state.history = Array(state.history.prefix(max(state.advancedPreferences.historyLimit, 1)))

            if !state.persistedMangas.contains(where: { $0.id == manga.id }) {
                state.persistedMangas.append(manga)
            }
        }
        persist()
    }
}

