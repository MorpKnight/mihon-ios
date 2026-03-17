//
//  AppModel+Repositories.swift
//  Mihon IOS
//

import Foundation

extension AppModel {
    // MARK: - SettingsRepository

    var preferences: AppPreferences {
        AppPreferences(
            reader: state.readerPreferences,
            library: state.libraryPreferences,
            app: state.appSettings,
            downloads: state.downloadPreferences,
            browse: state.browsePreferences,
            security: state.securityPreferences,
            advanced: state.advancedPreferences
        )
    }

    // MARK: - LibraryRepository

    var categories: [Category] {
        state.categories
    }

    func libraryEntries() -> [LibraryEntry] {
        state.library
    }

    // MARK: - ReaderProgressRepository

    func progressEntries() -> [ReadingProgress] {
        state.progress
    }

    func historyEntries() -> [HistoryEntry] {
        state.history
    }

    // MARK: - TrackingRepository

    func bindings() -> [TrackerBinding] {
        state.trackers
    }

    // MARK: - DownloadRepository

    func jobs() -> [DownloadJob] {
        downloadJobs.sorted { $0.queuedAt < $1.queuedAt }
    }

    // MARK: - BackupRepository

    func createPayload() -> BackupPayload {
        let itemCount = state.library.count + state.history.count + state.trackers.count + state.categories.count + importRecords.count
        return BackupPayload(
            id: UUID(),
            createdAt: .now,
            sections: ["Library", "History", "Categories", "Progress", "Trackers", "Preferences", "Source Repos", "Imports"],
            itemCount: itemCount
        )
    }

    // MARK: - MigrationRepository

    func migrationCandidates(for manga: Manga) -> [MigrationCandidate] {
        sources
            .filter { $0.id != manga.sourceID && $0.kind == .remote }
            .flatMap { source in
                mangas(for: source)
                    .filter { candidate in candidate.title.localizedCaseInsensitiveContains(manga.title.split(separator: " ").first.map(String.init) ?? manga.title) }
                    .map { MigrationCandidate(id: "\($0.id)-\(source.id)", source: source, manga: $0) }
            }
    }
}
