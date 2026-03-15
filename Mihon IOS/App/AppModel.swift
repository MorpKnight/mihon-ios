//
//  AppModel.swift
//  Mihon IOS
//

import Combine
import LocalAuthentication
import SwiftUI

enum BootState: Equatable {
    case launching
    case ready
    case failed(String)
}

private let biometricLockFeatureEnabled = true

@MainActor
final class AppModel: ObservableObject, LibraryRepository, ReaderProgressRepository, DownloadRepository, TrackingRepository, BackupRepository, SettingsRepository, MigrationRepository {
    @Published private(set) var state: PersistedState
    @Published private(set) var sources: [Source]
    @Published private(set) var bootState: BootState = .launching
    @Published private(set) var importRecords: [ImportRecord]
    @Published private(set) var importJobsState: [ImportJob]
    @Published private(set) var repoRecords: [SourceRepoRecord]
    @Published private(set) var sourceMangaCache: [String: [Manga]]
    @Published private(set) var sourceGenreCache: [String: [GenreTag]]
    @Published private(set) var chapterCache: [String: [Chapter]]
    @Published private(set) var pageCache: [String: [ReaderPage]]
    @Published private(set) var sourceErrors: [String: String]
    @Published private(set) var pageLoadErrors: [String: String]
    @Published private(set) var diagnosticLogs: [DiagnosticLogEntry]
    @Published private(set) var repoImportErrorMessage: String?
    @Published private(set) var importingRepoURL: String?
    @Published private(set) var isAppUnlocked = true
    @Published private(set) var biometricErrorMessage: String?
    @Published var releaseNotesPresented = true

    private let databaseCoordinator: FileDatabaseCoordinator
    private let legacyStore: AppStateStore
    private var repository: SourceRepository
    private let importRepository: FileImportRepository
    private let localContentRepository: LocalContentRepository
    private let readerAssetRepository: ReaderAssetRepository
    private let repoImporter: SourceRepoImporter

    init(
        store: AppStateStore = AppStateStore(),
        repository: SourceRepository? = nil,
        databaseCoordinator: FileDatabaseCoordinator? = nil,
        localContentRepository: LocalContentRepository = DefaultLocalContentRepository(),
        readerAssetRepository: ReaderAssetRepository = DefaultReaderAssetRepository(),
        repoImporter: SourceRepoImporter = SourceRepoImporter()
    ) {
        self.legacyStore = store
        self.databaseCoordinator = databaseCoordinator ?? FileDatabaseCoordinator(stateStore: store)
        self.localContentRepository = localContentRepository
        self.readerAssetRepository = readerAssetRepository
        self.repoImporter = repoImporter
        self.importRepository = FileImportRepository(coordinator: self.databaseCoordinator)

        let snapshot = self.databaseCoordinator.loadSnapshot()
        let hydratedRepoRecords = snapshot.repoRecords.isEmpty
            ? snapshot.state.sourceRepos.map {
                SourceRepoRecord(
                    id: $0,
                    url: $0,
                    title: URL(string: $0)?.host ?? $0,
                    fetchedAt: .distantPast,
                    packages: [],
                    importedSources: [],
                    lastError: "Repository pending import. Refresh by adding the URL again."
                )
            }
            : snapshot.repoRecords
        self.repository = repository ?? RuntimeSourceRepository(repoRecords: hydratedRepoRecords)
        var persistedState = snapshot.state
        persistedState.sourceRepos = hydratedRepoRecords.map(\.url)
        self.state = persistedState
        self.importRecords = snapshot.imports
        self.importJobsState = snapshot.importJobs
        self.repoRecords = hydratedRepoRecords
        self.sourceMangaCache = [:]
        self.sourceGenreCache = [:]
        self.chapterCache = [:]
        self.pageCache = [:]
        self.sourceErrors = [:]
        self.pageLoadErrors = [:]
        self.diagnosticLogs = snapshot.diagnostics
        self.repoImportErrorMessage = nil
        self.importingRepoURL = nil
        self.sources = self.repository.sources()

        seedInitialLibraryIfNeeded()
        bootState = .ready
    }

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

    var preferredColorScheme: ColorScheme? {
        guard !state.appSettings.useSystemColorScheme else { return nil }
        return state.appSettings.prefersDarkMode ? .dark : .light
    }

    var chromeTint: Color {
        Color(hex: "#2F6BFF")
    }

    var categories: [Category] {
        state.categories
    }

    var allManga: [Manga] {
        let remote = Dictionary(
            uniqueKeysWithValues: (
                repository.sources()
                    .filter { $0.kind == .remote }
                    .flatMap { repository.mangas(for: $0.id) } +
                sourceMangaCache.values.flatMap { $0 }
            ).map { ($0.id, $0) }
        )
        return remote.values.sorted { $0.title < $1.title } +
        localContentRepository.mangas(from: importRecords, sourceID: "local-files")
    }

    var currentLanguageLabel: String {
        state.appSettings.appLanguageCode == "system" ? "System Default" : state.appSettings.appLanguageCode.uppercased()
    }

    var supportsAdultSources: Bool {
        sources.contains { $0.allowsAdultContent }
    }

    var visibleSources: [Source] {
        sources.filter { source in
            sourceMatchesBrowseLanguagePreferences(source) &&
            (!state.browsePreferences.hideAdultSources || !source.allowsAdultContent) &&
            (!state.browsePreferences.enabledSourcesOnly || source.isEnabled) &&
            (!state.browsePreferences.pinnedSourcesOnly || source.isPinned)
        }
    }

    var sourceDescriptors: [SourceDescriptor] {
        repository.descriptors()
    }

    func markOnboardingCompleted() {
        state.onboardingCompleted = true
        persist()
    }

    func mangas(for source: Source) -> [Manga] {
        let items: [Manga]
        if source.kind == .local {
            items = localContentRepository.mangas(from: importRecords, sourceID: source.id)
        } else if let cached = sourceMangaCache[source.id], !cached.isEmpty {
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
        if let cached = chapterCache[manga.id], !cached.isEmpty {
            return cached
        }
        return repository.chapters(for: manga.id)
    }

    func libraryEntries() -> [LibraryEntry] {
        state.library
    }

    func progressEntries() -> [ReadingProgress] {
        state.progress
    }

    func historyEntries() -> [HistoryEntry] {
        state.history
    }

    func bindings() -> [TrackerBinding] {
        state.trackers
    }

    func jobs() -> [DownloadJob] {
        importRecords.flatMap { record in
            let manga = localContentRepository.mangas(from: [record], sourceID: "local-files").first!
            return localContentRepository.chapters(for: record.title.id, from: [record]).map { chapter in
                let pending = record.title.kind == .cbz || record.title.kind == .zip || record.title.kind == .epub
                return DownloadJob(
                    id: UUID(),
                    manga: manga,
                    chapter: chapter,
                    progress: pending ? 0.25 : 1.0,
                    state: pending ? .queued : .complete
                )
            }
        }
    }

    func createPayload() -> BackupPayload {
        let itemCount = state.library.count + state.history.count + state.trackers.count + state.categories.count + importRecords.count
        return BackupPayload(
            id: UUID(),
            createdAt: .now,
            sections: ["Library", "History", "Categories", "Progress", "Trackers", "Preferences", "Source Repos", "Imports"],
            itemCount: itemCount
        )
    }

    func migrationCandidates(for manga: Manga) -> [MigrationCandidate] {
        sources
            .filter { $0.id != manga.sourceID && $0.kind == .remote }
            .flatMap { source in
                mangas(for: source)
                    .filter { candidate in candidate.title.localizedCaseInsensitiveContains(manga.title.split(separator: " ").first.map(String.init) ?? manga.title) }
                    .map { MigrationCandidate(id: "\($0.id)-\(source.id)", source: source, manga: $0) }
            }
    }

    func latestChapter(for manga: Manga) -> Chapter? {
        chapters(for: manga).first
    }

    func progress(for manga: Manga) -> ReadingProgress? {
        state.progress.first { $0.mangaID == manga.id }
    }

    func note(for manga: Manga) -> String {
        state.mangaNotes[manga.id, default: ""]
    }

    func saveNote(_ note: String, for manga: Manga) {
        state.mangaNotes[manga.id] = note
        persist()
    }

    func trackerBindings(for manga: Manga) -> [TrackerBinding] {
        state.trackers.filter { $0.mangaID == manga.id }
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
        } else {
            state.library.insert(
                LibraryEntry(
                    mangaID: manga.id,
                    categoryID: state.libraryPreferences.defaultCategoryID,
                    addedAt: .now
                ),
                at: 0
            )
        }
        persist()
    }

    func assignCategory(_ categoryID: String, to manga: Manga) {
        guard let index = state.library.firstIndex(where: { $0.mangaID == manga.id }) else { return }
        state.library[index].categoryID = categoryID
        persist()
    }

    func categoryName(for id: String) -> String {
        categories.first(where: { $0.id == id })?.name ?? "Library"
    }

    func addCategory(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.categories.append(Category(id: UUID().uuidString, name: trimmed, systemImage: "folder"))
        persist()
    }

    func renameCategory(_ categoryID: String, to name: String) {
        guard let index = state.categories.firstIndex(where: { $0.id == categoryID }) else { return }
        state.categories[index].name = name
        persist()
    }

    func deleteCategory(_ categoryID: String) {
        guard state.categories.count > 1 else { return }
        state.categories.removeAll { $0.id == categoryID }
        let fallback = state.categories.first?.id ?? PersistedState.default.libraryPreferences.defaultCategoryID
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

    func chapter(for id: String, in manga: Manga) -> Chapter? {
        chapters(for: manga).first { $0.id == id }
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
        }
        persist()
    }

    func setReaderMode(_ mode: ReaderMode) {
        state.readerPreferences.mode = mode
        persist()
    }

    func setKeepAwake(_ enabled: Bool) {
        state.readerPreferences.keepAwake = enabled
        persist()
    }

    func setReaderOrientation(_ orientation: ReaderOrientation) {
        state.readerPreferences.orientation = orientation
        persist()
    }

    func setReaderPageNumberVisible(_ enabled: Bool) {
        state.readerPreferences.showPageNumber = enabled
        persist()
    }

    func setColorFilterEnabled(_ enabled: Bool) {
        state.readerPreferences.colorFilter.enabled = enabled
        persist()
    }

    func setColorFilterGrayscale(_ value: Double) {
        state.readerPreferences.colorFilter.grayscale = value
        persist()
    }

    func setColorFilterDimming(_ value: Double) {
        state.readerPreferences.colorFilter.dimming = value
        persist()
    }

    func setContinueReadingVisible(_ enabled: Bool) {
        state.libraryPreferences.showContinueReading = enabled
        persist()
    }

    func setDownloadedBadgeVisible(_ enabled: Bool) {
        state.libraryPreferences.showDownloadedBadge = enabled
        persist()
    }

    func setUnreadBadgeVisible(_ enabled: Bool) {
        state.libraryPreferences.showUnreadBadge = enabled
        persist()
    }

    func setLibrarySortMode(_ mode: LibrarySortMode) {
        state.libraryPreferences.sortMode = mode
        persist()
    }

    func setDefaultCategoryID(_ categoryID: String) {
        state.libraryPreferences.defaultCategoryID = categoryID
        persist()
    }

    func setUseSystemAppearance(_ enabled: Bool) {
        state.appSettings.useSystemColorScheme = enabled
        persist()
    }

    func setDarkModePreferred(_ enabled: Bool) {
        state.appSettings.prefersDarkMode = enabled
        persist()
    }

    func setDownloadedOnly(_ enabled: Bool) {
        state.appSettings.downloadedOnly = enabled
        persist()
    }

    func setIncognitoMode(_ enabled: Bool) {
        state.appSettings.incognitoMode = enabled
        persist()
    }

    func setAppLanguageCode(_ code: String) {
        state.appSettings.appLanguageCode = code
        persist()
    }

    func setDownloadWifiOnly(_ enabled: Bool) {
        state.downloadPreferences.wifiOnly = enabled
        persist()
    }

    func setAutoDownloadNewChapters(_ enabled: Bool) {
        state.downloadPreferences.autoDownloadNewChapters = enabled
        persist()
    }

    func setAutoDownloadUnreadOnly(_ enabled: Bool) {
        state.downloadPreferences.unreadOnly = enabled
        persist()
    }

    func setDownloadQueueStrategy(_ strategy: DownloadQueueStrategy) {
        state.downloadPreferences.queueStrategy = strategy
        persist()
    }

    func setBrowseLanguage(_ language: SourceLanguage, enabled: Bool) {
        if enabled {
            state.browsePreferences.enabledLanguages.insert(language)
        } else if state.browsePreferences.enabledLanguages.count > 1 {
            state.browsePreferences.enabledLanguages.remove(language)
        }
        persist()
    }

    func setHideAdultSources(_ enabled: Bool) {
        state.browsePreferences.hideAdultSources = enabled
        persist()
    }

    func setEnabledSourcesOnly(_ enabled: Bool) {
        state.browsePreferences.enabledSourcesOnly = enabled
        persist()
    }

    func setPinnedSourcesOnly(_ enabled: Bool) {
        state.browsePreferences.pinnedSourcesOnly = enabled
        persist()
    }

    func setBlurAppSwitcher(_ enabled: Bool) {
        state.securityPreferences.blurAppSwitcher = enabled
        persist()
    }

    func setLockLibraryEdits(_ enabled: Bool) {
        state.securityPreferences.lockLibraryEdits = enabled
        persist()
    }

    func setHideSensitiveCovers(_ enabled: Bool) {
        state.securityPreferences.hideSensitiveCovers = enabled
        persist()
    }

    func setBiometricUnlockEnabled(_ enabled: Bool) {
        state.securityPreferences.requireBiometricUnlock = biometricLockFeatureEnabled ? enabled : false
        isAppUnlocked = true
        biometricErrorMessage = biometricLockFeatureEnabled ? biometricErrorMessage : nil
        persist()
    }

    func setImagePrefetchCount(_ count: Int) {
        state.advancedPreferences.imagePrefetchCount = min(max(count, 0), 6)
        persist()
    }

    func setHistoryLimit(_ limit: Int) {
        state.advancedPreferences.historyLimit = min(max(limit, 20), 500)
        if state.history.count > state.advancedPreferences.historyLimit {
            state.history = Array(state.history.prefix(state.advancedPreferences.historyLimit))
        }
        persist()
    }

    func setShowDiagnostics(_ enabled: Bool) {
        state.advancedPreferences.showDiagnostics = enabled
        persist()
    }

    func setAggressiveImageRetry(_ enabled: Bool) {
        state.advancedPreferences.aggressiveImageRetry = enabled
        persist()
    }

    func sourceCatalogItems() -> [SourceCatalogItem] {
        let builtInItems = [
            SourceCatalogItem(
                id: "official-json",
                title: "Official JSON Catalog",
                summary: "Primary source catalog metadata package for browse and source discovery on iOS.",
                version: "1.0.0",
                isInstalled: true,
                hasUpdate: false,
                isTrusted: true,
                languages: [.multi, .english],
                languageCodes: ["all", "multi", "en"],
                sources: visibleSources.filter { $0.kind == .remote && descriptor(for: $0.id)?.origin == "built-in" },
                originLabel: "Built-in",
                supportStatus: .live
            ),
            SourceCatalogItem(
                id: "local-tooling",
                title: "Local Import Toolkit",
                summary: "Local archive and folder importer for CBZ, ZIP, EPUB metadata, and image directories.",
                version: "1.1.0",
                isInstalled: true,
                hasUpdate: false,
                isTrusted: true,
                languages: [.multi],
                languageCodes: ["all", "multi"],
                sources: visibleSources.filter { $0.kind == .local },
                originLabel: "Built-in",
                supportStatus: .live
            ),
        ]

        let importedItems = repoRecords.flatMap { record in
            record.packages.map { package in
                let packageSources = package.sources.compactMap { imported in
                    resolvedSource(for: imported)
                }
                let packageStatus = package.sources.map(\.supportStatus).contains(.live)
                    ? SourceSupportStatus.live
                    : (package.sources.map(\.supportStatus).contains(.planned) ? .planned : .unsupported)
                return SourceCatalogItem(
                    id: "\(record.id)::\(package.id)",
                    title: package.name,
                    summary: record.lastError ?? "Imported from \(record.title) with \(package.sources.count) source(s).",
                    version: package.version,
                    isInstalled: true,
                    hasUpdate: false,
                    isTrusted: record.url.hasPrefix("https://"),
                    languages: Array(Set(package.sources.map(\.language))).sorted { $0.rawValue < $1.rawValue },
                    languageCodes: Array(Set(package.sources.map { normalizeLanguageCode($0.languageCode) })).sorted(),
                    sources: packageSources,
                    originLabel: record.title,
                    supportStatus: packageStatus
                )
            }
        }

        return builtInItems + importedItems
    }

    func sourcePreferences(for source: Source) -> [SourcePreference] {
        let descriptor = repository.descriptor(for: source.id)
        let importedCount = source.kind == .local ? "\(importRecords.count) imported title(s)" : "Catalog metadata"
        let languageValue = descriptor?.languageCode.map(languageFilterTitle(for:)) ?? source.language.rawValue
        return [
            SourcePreference(id: "\(source.id)-family", title: "Engine Family", value: source.engineFamily.title),
            SourcePreference(id: "\(source.id)-runtime", title: "Runtime", value: descriptor?.supportStatus.title ?? "Planned"),
            SourcePreference(id: "\(source.id)-lang", title: "Language", value: languageValue),
            SourcePreference(id: "\(source.id)-status", title: "Status", value: source.isEnabled ? "Enabled" : "Disabled"),
            SourcePreference(id: "\(source.id)-policy", title: "Adult Policy", value: source.allowsAdultContent ? "Allowed" : "Safe"),
            SourcePreference(id: "\(source.id)-imports", title: "Storage", value: importedCount),
            SourcePreference(id: "\(source.id)-caps", title: "Capabilities", value: descriptor.map { $0.capabilities.map(\.rawValue).sorted().joined(separator: ", ") } ?? "Unknown"),
            SourcePreference(id: "\(source.id)-origin", title: "Origin", value: descriptor?.origin ?? "Built-in"),
            SourcePreference(id: "\(source.id)-package", title: "Package", value: descriptor?.packageName ?? "N/A"),
            SourcePreference(id: "\(source.id)-version", title: "Version", value: descriptor?.version ?? "N/A"),
        ]
    }

    func addSourceRepo(_ url: String) async {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        importingRepoURL = trimmed
        defer { importingRepoURL = nil }

        do {
            let record = try await repoImporter.importRepo(from: trimmed)
            repoRecords.removeAll { $0.url == record.url }
            repoRecords.insert(record, at: 0)
            state.sourceRepos = repoRecords.map(\.url)
            repoImportErrorMessage = nil
            appendDiagnostic(kind: .repo, title: "Repo Imported", message: "Imported \(record.importedSources.count) source(s) from \(record.title).", metadata: ["url": record.url])
            rebuildSourceRepository()
            persist()
        } catch {
            let failed = repoImporter.failedRecord(for: trimmed, error: error)
            repoRecords.removeAll { $0.url == failed.url }
            repoRecords.insert(failed, at: 0)
            state.sourceRepos = repoRecords.map(\.url)
            repoImportErrorMessage = failed.lastError
            appendDiagnostic(kind: .repo, title: "Repo Import Failed", message: failed.lastError ?? error.localizedDescription, metadata: ["url": failed.url])
            rebuildSourceRepository()
            persist()
        }
    }

    func refreshSourceRepo(_ url: String) async {
        guard let existing = repoRecords.first(where: { $0.url == url }) else {
            await addSourceRepo(url)
            return
        }

        importingRepoURL = existing.url
        defer { importingRepoURL = nil }

        let refreshed = await repoImporter.refresh(existing)
        repoRecords.removeAll { $0.url == existing.url }
        repoRecords.insert(refreshed, at: 0)
        state.sourceRepos = repoRecords.map(\.url)
        repoImportErrorMessage = refreshed.lastError
        appendDiagnostic(
            kind: .repo,
            title: refreshed.lastError == nil ? "Repo Refreshed" : "Repo Refresh Failed",
            message: refreshed.lastError ?? "Refreshed \(refreshed.importedSources.count) source(s) from \(refreshed.title).",
            metadata: ["url": refreshed.url]
        )
        rebuildSourceRepository()
        persist()
    }

    func refreshAllSourceRepos() async {
        let urls = repoRecords.map(\.url)
        guard !urls.isEmpty else { return }
        repoImportErrorMessage = nil
        for url in urls {
            await refreshSourceRepo(url)
        }
    }

    func removeSourceRepo(_ url: String) {
        state.sourceRepos.removeAll { $0 == url }
        repoRecords.removeAll { $0.url == url }
        repoImportErrorMessage = nil
        appendDiagnostic(kind: .repo, title: "Repo Removed", message: "Removed source repository.", metadata: ["url": url])
        rebuildSourceRepository()
        persist()
    }

    func linkTracker(service: TrackerService, to manga: Manga) {
        guard !state.trackers.contains(where: { $0.mangaID == manga.id && $0.service == service }) else { return }
        state.trackers.append(
            TrackerBinding(
                id: UUID(),
                mangaID: manga.id,
                service: service,
                remoteTitle: manga.title,
                status: "Reading",
                progressText: progress(for: manga).map { "\($0.pageIndex + 1) pages" } ?? "Started",
                score: "-"
            )
        )
        persist()
    }

    func unlinkTracker(_ binding: TrackerBinding) {
        state.trackers.removeAll { $0.id == binding.id }
        persist()
    }

    func statsSummary() -> [StatsItem] {
        [
            StatsItem(title: "Library Titles", value: "\(state.library.count)", systemImage: "books.vertical"),
            StatsItem(title: "Tracked Titles", value: "\(state.trackers.count)", systemImage: "person.badge.clock"),
            StatsItem(title: "Imported Titles", value: "\(importRecords.count)", systemImage: "tray.and.arrow.down"),
            StatsItem(title: "History Entries", value: "\(state.history.count)", systemImage: "clock.arrow.circlepath"),
        ]
    }

    func source(for id: String) -> Source? {
        sources.first { $0.id == id }
    }

    func sourceWebURL(for source: Source, manga: Manga? = nil) -> URL? {
        if source.id == "kiryuu-id" {
            if let manga, let slug = manga.id.components(separatedBy: "::").last {
                return URL(string: "https://v1.kiryuu.to/manga/\(slug)/")
            }
            return URL(string: "https://v1.kiryuu.to")
        }
        if let baseURL = descriptor(for: source.id)?.baseURL, let url = URL(string: baseURL) {
            return url
        }
        return URL(string: "https://mihon.app")
    }

    func supportsLiveSource(_ source: Source) -> Bool {
        guard let descriptor = repository.descriptor(for: source.id) else { return false }
        return source.kind == .remote && descriptor.supportStatus == .live
    }

    func supportsLiveSource(sourceID: String) -> Bool {
        sources.contains { $0.id == sourceID && supportsLiveSource($0) }
    }

    func descriptor(for sourceID: String) -> SourceDescriptor? {
        repository.descriptor(for: sourceID)
    }

    func sourceError(for sourceID: String) -> String? {
        sourceErrors[sourceID]
    }

    func pageLoadError(for chapterID: String) -> String? {
        pageLoadErrors[chapterID]
    }

    func genreTags(for sourceID: String) -> [GenreTag] {
        sourceGenreCache[sourceID] ?? []
    }

    func resolvedChapter(_ chapter: Chapter) -> Chapter {
        guard let pages = pageCache[chapter.id], !pages.isEmpty else { return chapter }
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
            sourceMangaCache[source.id] = items
            sourceErrors[source.id] = nil
        } catch {
            sourceErrors[source.id] = error.localizedDescription
            appendDiagnostic(kind: .source, title: "Source Feed Failed", message: error.localizedDescription, metadata: ["source": source.name, "mode": mode.rawValue])
        }
    }

    func loadGenreTags(for source: Source) async {
        guard supportsLiveSource(source), sourceGenreCache[source.id] == nil else { return }
        do {
            sourceGenreCache[source.id] = try await repository.genreTags(sourceID: source.id)
        } catch {
            sourceErrors[source.id] = error.localizedDescription
            appendDiagnostic(kind: .source, title: "Genre Load Failed", message: error.localizedDescription, metadata: ["source": source.name])
        }
    }

    func refreshMangaDetails(for manga: Manga) async -> Manga {
        guard supportsLiveSource(sourceID: manga.sourceID) else {
            return manga
        }
        do {
            let details = try await repository.mangaDetails(sourceID: manga.sourceID, mangaIDOrURL: manga.id)
            replaceCachedManga(details.manga, for: manga.sourceID)
            sourceErrors[manga.sourceID] = nil
            return details.manga
        } catch {
            sourceErrors[manga.sourceID] = error.localizedDescription
            appendDiagnostic(kind: .source, title: "Manga Detail Failed", message: error.localizedDescription, metadata: ["sourceID": manga.sourceID, "manga": manga.title])
            return manga
        }
    }

    func refreshChapters(for manga: Manga) async -> [Chapter] {
        if manga.sourceID == "local-files" {
            return chapters(for: manga)
        }
        do {
            let details = try await repository.chapters(sourceID: manga.sourceID, manga: manga)
            chapterCache[manga.id] = details.chapters
            sourceErrors[manga.sourceID] = nil
            return details.chapters
        } catch {
            sourceErrors[manga.sourceID] = error.localizedDescription
            appendDiagnostic(kind: .source, title: "Chapter Load Failed", message: error.localizedDescription, metadata: ["sourceID": manga.sourceID, "manga": manga.title])
            return chapters(for: manga)
        }
    }

    func refreshPages(for chapter: Chapter, sourceID: String) async -> [ReaderPage] {
        guard chapter.pages.isEmpty else {
            pageCache[chapter.id] = chapter.pages
            pageLoadErrors[chapter.id] = nil
            return chapter.pages
        }
        do {
            let details = try await repository.pages(sourceID: sourceID, chapter: chapter)
            pageCache[chapter.id] = details.pages
            pageLoadErrors[chapter.id] = details.errorMessage
            sourceErrors[sourceID] = nil
            if let warning = details.errorMessage, !warning.isEmpty {
                appendDiagnostic(kind: .reader, title: "Page Load Warning", message: warning, metadata: ["sourceID": sourceID, "chapterID": chapter.id])
            }
            return details.pages
        } catch {
            sourceErrors[sourceID] = error.localizedDescription
            pageLoadErrors[chapter.id] = error.localizedDescription
            appendDiagnostic(kind: .reader, title: "Page Load Failed", message: error.localizedDescription, metadata: ["sourceID": sourceID, "chapterID": chapter.id])
            return pageCache[chapter.id] ?? []
        }
    }

    func retryPages(for chapter: Chapter, sourceID: String) async -> [ReaderPage] {
        pageCache[chapter.id] = nil
        pageLoadErrors[chapter.id] = nil
        return await refreshPages(for: chapter, sourceID: sourceID)
    }

    func globalSearchResults(query: String) -> [(Source, [Manga])] {
        visibleSources.compactMap { source in
            let results = mangas(for: source).filter {
                query.isEmpty ||
                $0.title.localizedCaseInsensitiveContains(query) ||
                $0.author.localizedCaseInsensitiveContains(query) ||
                $0.genres.joined(separator: " ").localizedCaseInsensitiveContains(query)
            }
            return results.isEmpty ? nil : (source, results)
        }
    }

    func importItems(from urls: [URL]) {
        do {
            let result = try importRepository.importItems(from: urls)
            importRecords = result.records
            importJobsState = result.jobs
        } catch {
            appendDiagnostic(kind: .app, title: "Local Import Failed", message: error.localizedDescription, metadata: [:])
            bootState = .failed("Failed to import local content: \(error.localizedDescription)")
        }
    }

    func importedJobs() -> [ImportJob] {
        importJobsState
    }

    func fileURL(for page: ReaderPage) -> URL? {
        readerAssetRepository.fileURL(for: page)
    }

    func localImportSummary() -> String {
        importRecords.isEmpty ? "No local titles imported yet." : "\(importRecords.count) local title(s) available."
    }

    func storageSummary() -> String {
        "\(state.library.count) library • \(importRecords.count) imports • \(state.history.count) history"
    }

    func diagnosticsSummary() -> [String] {
        [
            "Schema v\(state.schemaVersion)",
            "Sources: \(visibleSources.count)/\(sources.count)",
            "Source repos: \(state.sourceRepos.count)",
            "Page cache: \(pageCache.count)",
            "Chapter cache: \(chapterCache.count)",
            "Error logs: \(diagnosticLogs.count)",
        ]
    }

    func clearDiagnostics() {
        diagnosticLogs.removeAll()
        persist()
    }

    func resetOnboarding() {
        state.onboardingCompleted = false
        persist()
    }

    func clearImageCache() async {
        await ReaderImagePipeline.shared.clear()
    }

    func lockAppIfNeeded() {
        guard biometricLockFeatureEnabled, state.securityPreferences.requireBiometricUnlock else { return }
        isAppUnlocked = false
    }

    func unlockAppIfNeeded() async {
        guard biometricLockFeatureEnabled, state.securityPreferences.requireBiometricUnlock, !isAppUnlocked else { return }
        await requestBiometricUnlock()
    }

    func requestBiometricUnlock() async {
        guard biometricLockFeatureEnabled, state.securityPreferences.requireBiometricUnlock else {
            isAppUnlocked = true
            biometricErrorMessage = nil
            return
        }

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var authError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            biometricErrorMessage = authError?.localizedDescription ?? "Face ID is not available on this device."
            appendDiagnostic(kind: .security, title: "Biometric Unavailable", message: biometricErrorMessage ?? "Face ID is not available.", metadata: [:])
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock Mihon to continue reading and browsing."
            )
            if success {
                isAppUnlocked = true
                biometricErrorMessage = nil
            }
        } catch {
            biometricErrorMessage = error.localizedDescription
            appendDiagnostic(kind: .security, title: "Biometric Unlock Failed", message: error.localizedDescription, metadata: [:])
        }
    }

    private func seedInitialLibraryIfNeeded() {
        guard state.library.isEmpty else { return }
    }

    private func persist() {
        state.schemaVersion = PersistedState.currentSchemaVersion
        state.sourceRepos = repoRecords.map(\.url)
        let snapshot = DatabaseSnapshot(state: state, imports: importRecords, importJobs: importJobsState, repoRecords: repoRecords, diagnostics: diagnosticLogs)
        databaseCoordinator.saveSnapshot(snapshot)
        legacyStore.save(state)
    }

    private func rebuildSourceRepository() {
        repository = RuntimeSourceRepository(repoRecords: repoRecords)
        sources = repository.sources()
    }

    private func replaceCachedManga(_ manga: Manga, for sourceID: String) {
        var items = sourceMangaCache[sourceID] ?? []
        if let index = items.firstIndex(where: { $0.id == manga.id || $0.title == manga.title }) {
            items[index] = manga
        } else {
            items.insert(manga, at: 0)
        }
        sourceMangaCache[sourceID] = items
    }

    private func appendDiagnostic(kind: DiagnosticLogKind, title: String, message: String, metadata: [String: String]) {
        diagnosticLogs.insert(
            DiagnosticLogEntry(
                id: UUID(),
                timestamp: .now,
                kind: kind,
                title: title,
                message: message,
                metadata: metadata
            ),
            at: 0
        )
        diagnosticLogs = Array(diagnosticLogs.prefix(200))
    }

    private func resolvedSource(for imported: ImportedSourceDescriptor) -> Source? {
        if let direct = sources.first(where: { $0.id == imported.sourceID }) {
            return direct
        }
        return sources.first { source in
            guard let descriptor = descriptor(for: source.id) else { return false }
            return descriptor.engineFamily == imported.engineFamily &&
                descriptor.baseURL?.caseInsensitiveCompare(imported.baseURL) == .orderedSame
        }
    }

    func defaultCatalogLanguageCodes() -> Set<String> {
        var languageCodes = Set<String>()
        for language in state.browsePreferences.enabledLanguages {
            languageCodes.formUnion(codes(for: language))
        }
        return languageCodes
    }

    func languageFilterTitle(for code: String) -> String {
        switch normalizeLanguageCode(code) {
        case "en": return "English"
        case "id": return "Indonesian"
        case "ja", "jp": return "Japanese"
        case "all", "multi": return "Multi"
        default: return code.uppercased()
        }
    }

    func sourceCatalogLanguageFilters() -> [(id: String, title: String)] {
        let codes = Set(sourceCatalogItems().flatMap(\.languageCodes).map(normalizeLanguageCode)).sorted()
        let dynamic = codes.map { (id: $0, title: languageFilterTitle(for: $0)) }
        return [("preferred", "Preferred"), ("all", "All")] + dynamic
    }

    func catalogItems(matchingLanguageFilter filterID: String) -> [SourceCatalogItem] {
        let items = sourceCatalogItems()
        switch filterID {
        case "all":
            return items
        case "preferred":
            let preferred = defaultCatalogLanguageCodes()
            return items.filter { item in
                item.languageCodes.isEmpty || !preferred.isDisjoint(with: Set(item.languageCodes.map(normalizeLanguageCode)))
            }
        default:
            let wanted = normalizeLanguageCode(filterID)
            return items.filter { item in
                item.languageCodes.contains(where: { normalizeLanguageCode($0) == wanted })
            }
        }
    }

    private func sourceMatchesBrowseLanguagePreferences(_ source: Source) -> Bool {
        if let code = descriptor(for: source.id)?.languageCode {
            return defaultCatalogLanguageCodes().contains(normalizeLanguageCode(code))
        }
        return state.browsePreferences.enabledLanguages.contains(source.language)
    }

    private func codes(for language: SourceLanguage) -> Set<String> {
        switch language {
        case .english:
            return ["en"]
        case .indonesian:
            return ["id"]
        case .japanese:
            return ["ja", "jp"]
        case .multi:
            return ["all", "multi"]
        }
    }

    private func normalizeLanguageCode(_ code: String) -> String {
        let lowered = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch lowered {
        case "jp":
            return "ja"
        default:
            return lowered
        }
    }
}

enum LibrarySortMode: String, Codable, CaseIterable, Identifiable {
    case recent
    case alphabetical
    case chapterCount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: return "Recent"
        case .alphabetical: return "A-Z"
        case .chapterCount: return "Chapters"
        }
    }
}

struct StatsItem: Identifiable, Hashable {
    var id: String { title }
    let title: String
    let value: String
    let systemImage: String
}
