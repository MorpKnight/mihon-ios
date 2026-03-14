//
//  ServiceContracts.swift
//  Mihon IOS
//

import Foundation

protocol SourceRepository {
    func sources() -> [Source]
    func mangas(for sourceID: String) -> [Manga]
    func chapters(for mangaID: String) -> [Chapter]
    func activeSources() -> [Source]
    func popularManga(sourceID: String) async throws -> [Manga]
    func latestManga(sourceID: String) async throws -> [Manga]
    func searchManga(sourceID: String, query: String, filters: [SourceFilterValue]) async throws -> [Manga]
    func mangaDetails(sourceID: String, mangaIDOrURL: String) async throws -> SourceMangaDetails
    func chapters(sourceID: String, manga: Manga) async throws -> SourceChapterDetails
    func pages(sourceID: String, chapter: Chapter) async throws -> SourcePageAsset
    func genreTags(sourceID: String) async throws -> [GenreTag]
}

protocol DatabaseCoordinator {
    var databaseDirectoryURL: URL { get }
    func loadSnapshot() -> DatabaseSnapshot
    func saveSnapshot(_ snapshot: DatabaseSnapshot)
}

protocol LibraryRepository {
    var categories: [Category] { get }
    func libraryEntries() -> [LibraryEntry]
}

protocol ReaderProgressRepository {
    func progressEntries() -> [ReadingProgress]
    func historyEntries() -> [HistoryEntry]
}

protocol DownloadRepository {
    func jobs() -> [DownloadJob]
}

protocol TrackingRepository {
    func bindings() -> [TrackerBinding]
}

protocol BackupRepository {
    func createPayload() -> BackupPayload
}

protocol SettingsRepository {
    var preferences: AppPreferences { get }
}

protocol MigrationRepository {
    func migrationCandidates(for manga: Manga) -> [MigrationCandidate]
}

protocol ImportRepository {
    func importItems(from urls: [URL]) throws -> ImportResult
    func records() -> [ImportRecord]
    func jobs() -> [ImportJob]
}

protocol LocalContentRepository {
    func mangas(from records: [ImportRecord], sourceID: String) -> [Manga]
    func chapters(for mangaID: String, from records: [ImportRecord]) -> [Chapter]
}

protocol ReaderAssetRepository {
    func fileURL(for page: ReaderPage) -> URL?
}
