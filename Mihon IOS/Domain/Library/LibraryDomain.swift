//
//  LibraryDomain.swift
//  Mihon IOS
//

import Foundation

struct Category: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    let systemImage: String
}

struct LibraryEntry: Identifiable, Codable, Hashable {
    var id: String { mangaID }
    let mangaID: String
    var categoryID: String
    let addedAt: Date
}

struct ReadingProgress: Identifiable, Codable, Hashable {
    var id: String { mangaID }
    let mangaID: String
    var chapterID: String
    var pageIndex: Int
    var totalPages: Int
    var updatedAt: Date
}

struct HistoryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let mangaID: String
    let chapterID: String
    let pageIndex: Int
    let timestamp: Date
}

struct UpdateEntry: Identifiable, Hashable {
    let id: String
    let mangaID: String
    let chapterID: String
    let sourceID: String
    let isBookmarked: Bool
}

struct LibraryManga: Identifiable, Hashable {
    let id: String
    let manga: Manga
    let entry: LibraryEntry
    let progress: ReadingProgress?
    let latestChapter: Chapter?
}

struct UpdateFeedItem: Identifiable, Hashable {
    let id: String
    let manga: Manga
    let chapter: Chapter
    let entry: UpdateEntry
}

