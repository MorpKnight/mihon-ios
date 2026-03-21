//
//  AppModel+Library.swift
//  Mihon IOS
//

import Foundation

extension AppModel {
    private var uncategorizedCategoryID: String { "" }

    func note(for manga: Manga) -> String {
        state.mangaNotes[manga.id, default: ""]
    }

    func saveNote(_ note: String, for manga: Manga) {
        state.mangaNotes[manga.id] = note
        persist()
    }

    func libraryCategory(for manga: Manga) -> Category? {
        guard let entry = state.library.first(where: { $0.mangaID == manga.id }) else { return nil }
        return categories.first(where: { $0.id == entry.categoryID })
    }

    func isInLibrary(_ manga: Manga) -> Bool {
        state.library.contains { $0.mangaID == manga.id }
    }

    func toggleLibrary(_ manga: Manga) {
        if isInLibrary(manga) {
            state.library.removeAll { $0.mangaID == manga.id }

            // Cleanup persisted backup if history doesn't mention it and the user has no offline downloads.
            let hasOfflineDownloads = peekCachedChapters(for: manga.id)?.contains(where: \.isDownloaded) ?? false
            if !hasOfflineDownloads, !state.history.contains(where: { $0.mangaID == manga.id }) {
                state.persistedMangas.removeAll { $0.id == manga.id }
            }
        } else {
            state.library.insert(
                LibraryEntry(
                    mangaID: manga.id,
                    categoryID: resolvedDefaultCategoryID(),
                    addedAt: .now
                ),
                at: 0
            )
            if !state.persistedMangas.contains(where: { $0.id == manga.id }) {
                state.persistedMangas.append(manga)
            }
            ensureMangaCached(manga)
        }
        persist()
    }

    func assignCategory(_ categoryID: String, to manga: Manga) {
        guard let index = state.library.firstIndex(where: { $0.mangaID == manga.id }) else { return }
        state.library[index].categoryID = categoryID
        persist()
    }

    func categoryName(for id: String) -> String {
        if id.isEmpty {
            return "Uncategorized"
        }
        return categories.first(where: { $0.id == id })?.name ?? "Uncategorized"
    }

    func resolvedDefaultCategoryID() -> String {
        if let preferred = categories.first(where: { $0.id == state.libraryPreferences.defaultCategoryID }) {
            return preferred.id
        }
        return categories.first?.id ?? uncategorizedCategoryID
    }

    func addCategory(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let category = Category(id: UUID().uuidString, name: trimmed, systemImage: "folder")
        state.categories.append(category)
        if state.libraryPreferences.defaultCategoryID.isEmpty {
            state.libraryPreferences.defaultCategoryID = category.id
        }
        persist()
    }

    func renameCategory(_ categoryID: String, to name: String) {
        guard let index = state.categories.firstIndex(where: { $0.id == categoryID }) else { return }
        state.categories[index].name = name
        persist()
    }

    func deleteCategory(_ categoryID: String) {
        state.categories.removeAll { $0.id == categoryID }
        let fallback = state.categories.first?.id ?? uncategorizedCategoryID
        if state.libraryPreferences.defaultCategoryID == categoryID {
            state.libraryPreferences.defaultCategoryID = fallback
        }
        for index in state.library.indices where state.library[index].categoryID == categoryID {
            state.library[index].categoryID = fallback
        }
        persist()
    }

    func libraryItems(selectedCategoryID: String?, searchText: String = "", sortMode: LibrarySortMode = .recent) -> [LibraryManga] {
        let filtered: [LibraryManga] = state.library
            .filter { selectedCategoryID == nil || $0.categoryID == selectedCategoryID }
            .compactMap { entry -> LibraryManga? in
                guard let manga = allManga.first(where: { $0.id == entry.mangaID }) else { return nil }
                return LibraryManga(
                    id: manga.id,
                    manga: manga,
                    entry: entry,
                    progress: progress(for: manga),
                    latestChapter: latestChapter(for: manga)
                )
            }
            .filter { item in
                searchText.isEmpty || item.manga.title.localizedCaseInsensitiveContains(searchText)
            }
            .filter { item in
                guard state.appSettings.downloadedOnly else { return true }
                return chapters(for: item.manga).contains(where: \.isDownloaded)
            }

        switch sortMode {
        case .recent:
            return filtered.sorted { ($0.progress?.updatedAt ?? $0.entry.addedAt) > ($1.progress?.updatedAt ?? $1.entry.addedAt) }
        case .alphabetical:
            return filtered.sorted { $0.manga.title < $1.manga.title }
        case .chapterCount:
            return filtered.sorted { chapters(for: $0.manga).count > chapters(for: $1.manga).count }
        }
    }

    func preferredLibrarySortMode() -> LibrarySortMode {
        state.libraryPreferences.sortMode
    }

    var continueReadingItems: [LibraryManga] {
        libraryItems(selectedCategoryID: nil)
            .filter { $0.progress != nil }
    }

    private func ensureMangaCached(_ manga: Manga) {
        guard manga.sourceID != "local-files" else { return }
        var items = cachedSourceManga(for: manga.sourceID) ?? []
        if !items.contains(where: { $0.id == manga.id }) {
            items.append(manga)
            setCachedSourceManga(items, for: manga.sourceID)
        }
    }
}
