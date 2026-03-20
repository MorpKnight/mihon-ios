//
//  AppModel.swift
//  Mihon IOS
//

import Combine
import Foundation
import SwiftUI
import UIKit

enum BootState: Equatable {
    case launching
    case ready
    case failed(String)
}

@MainActor
final class AppModel: ObservableObject, LibraryRepository, ReaderProgressRepository, DownloadRepository, TrackingRepository, BackupRepository, SettingsRepository, MigrationRepository {
    static let biometricLockFeatureEnabled = true

    @Published internal(set) var state: PersistedState
    @Published internal(set) var sources: [Source]
    @Published internal(set) var bootState: BootState = .launching
    @Published internal(set) var importRecords: [ImportRecord]
    @Published internal(set) var importJobsState: [ImportJob]
    @Published internal(set) var repoRecords: [SourceRepoRecord]
    @Published internal(set) var sourceMangaCache: [String: [Manga]]
    @Published internal(set) var sourceGenreCache: [String: [GenreTag]]
    @Published internal(set) var chapterCache: [String: [Chapter]]
    @Published internal(set) var pageCache: [String: [ReaderPage]]
    @Published internal(set) var sourceErrors: [String: String]
    @Published internal(set) var pageLoadErrors: [String: String]
    @Published internal(set) var diagnosticLogs: [DiagnosticLogEntry]
    @Published internal(set) var repoImportErrorMessage: String?
    @Published internal(set) var importingRepoURL: String?
    @Published internal(set) var isAppUnlocked = true
    @Published internal(set) var biometricErrorMessage: String?
    @Published internal(set) var cacheStats = CacheStats(
        memoryImageCount: 0,
        memoryDataCount: 0,
        diskImageBytes: 0,
        diskMetadataBytes: 0,
        diskNetworkBytes: 0,
        hitCount: 0,
        missCount: 0
    )
    @Published internal(set) var downloadJobs: [DownloadJob] = []
    @Published var releaseNotesPresented = false

    private let databaseCoordinator: FileDatabaseCoordinator
    private let legacyStore: AppStateStore
    private let sourceMangaRuntimeCache: RuntimeCacheStore<String, [Manga]>
    private let sourceGenreRuntimeCache: RuntimeCacheStore<String, [GenreTag]>
    private let chapterRuntimeCache: RuntimeCacheStore<String, [Chapter]>
    private let pageRuntimeCache: RuntimeCacheStore<String, [ReaderPage]>

    var repository: SourceRepository
    let importRepository: FileImportRepository
    let localContentRepository: LocalContentRepository
    let readerAssetRepository: ReaderAssetRepository
    let repoImporter: SourceRepoImporter
    let cacheController: AppCacheManaging
    let biometricAuthenticator: BiometricAuthenticating
    let downloadsService: DownloadsServicing
    let downloadQueueCoordinator: DownloadQueueCoordinating
    let backgroundTaskManager: BackgroundTaskManaging

    init(
        store: AppStateStore,
        repository: SourceRepository? = nil,
        databaseCoordinator: FileDatabaseCoordinator? = nil,
        localContentRepository: LocalContentRepository,
        readerAssetRepository: ReaderAssetRepository,
        repoImporter: SourceRepoImporter,
        cacheController: AppCacheManaging,
        biometricAuthenticator: BiometricAuthenticating,
        downloadsService: DownloadsServicing,
        downloadQueueCoordinator: DownloadQueueCoordinating,
        backgroundTaskManager: BackgroundTaskManaging
    ) {
        self.legacyStore = store
        self.databaseCoordinator = databaseCoordinator ?? FileDatabaseCoordinator(stateStore: store)
        self.localContentRepository = localContentRepository
        self.readerAssetRepository = readerAssetRepository
        self.repoImporter = repoImporter
        self.cacheController = cacheController
        self.biometricAuthenticator = biometricAuthenticator
        self.downloadsService = downloadsService
        self.downloadQueueCoordinator = downloadQueueCoordinator
        self.backgroundTaskManager = backgroundTaskManager
        self.importRepository = FileImportRepository(coordinator: self.databaseCoordinator)

        let snapshot = self.databaseCoordinator.loadSnapshot()
        self.sourceMangaRuntimeCache = RuntimeCacheStore(
            countLimit: Self.defaultSourceMangaCacheEntries
        )
        self.sourceGenreRuntimeCache = RuntimeCacheStore(
            countLimit: Self.defaultSourceGenreCacheEntries
        )
        self.chapterRuntimeCache = RuntimeCacheStore(
            countLimit: max(Self.defaultChapterCacheEntries, snapshot.downloadedChapters.count),
            seed: snapshot.downloadedChapters
        )
        self.pageRuntimeCache = RuntimeCacheStore(
            countLimit: Self.defaultPageCacheEntries
        )
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
        self.repository = repository ?? RuntimeSourceRepository(repoRecords: hydratedRepoRecords, cache: cacheController)
        var persistedState = snapshot.state
        persistedState.sourceRepos = hydratedRepoRecords.map(\.url)
        self.state = persistedState
        self.importRecords = snapshot.imports
        self.importJobsState = snapshot.importJobs
        self.repoRecords = hydratedRepoRecords
        self.sourceMangaCache = sourceMangaRuntimeCache.snapshot()
        self.sourceGenreCache = [:]
        self.chapterCache = chapterRuntimeCache.snapshot()
        self.pageCache = pageRuntimeCache.snapshot()
        self.sourceErrors = [:]
        self.pageLoadErrors = [:]
        self.diagnosticLogs = snapshot.diagnostics
        self.repoImportErrorMessage = nil
        self.importingRepoURL = nil
        self.sources = self.repository.sources()

        seedInitialLibraryIfNeeded()

        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        if persistedState.appSettings.releaseNotesSeenVersion != currentVersion {
            self.releaseNotesPresented = true
            self.state.appSettings.releaseNotesSeenVersion = currentVersion
            // Cannot call normal class methods yet, but init covers initial state; we will call persist after init formally completes or rely on subsequent persists.
        }

        bootState = .ready
        Task { await applyCacheConfiguration() }
        Task { await refreshCacheStats() }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.respondToMemoryPressure()
            }
        }
    }

    convenience init() {
        self.init(
            store: AppStateStore(),
            repository: nil,
            databaseCoordinator: nil,
            localContentRepository: DefaultLocalContentRepository(),
            readerAssetRepository: DefaultReaderAssetRepository(),
            repoImporter: SourceRepoImporter(),
            cacheController: AppCacheController.shared,
            biometricAuthenticator: LocalBiometricAuthenticator(),
            downloadsService: DefaultDownloadsService(),
            downloadQueueCoordinator: DownloadQueueCoordinator(),
            backgroundTaskManager: AppBackgroundTaskManager()
        )
    }

    convenience init(dependencies: AppDependencies) {
        self.init(
            store: dependencies.store,
            repository: dependencies.repository,
            databaseCoordinator: dependencies.databaseCoordinator,
            localContentRepository: dependencies.localContentRepository,
            readerAssetRepository: dependencies.readerAssetRepository,
            repoImporter: dependencies.repoImporter,
            cacheController: dependencies.cacheController,
            biometricAuthenticator: dependencies.biometricAuthenticator,
            downloadsService: dependencies.downloadsService,
            downloadQueueCoordinator: dependencies.downloadQueueCoordinator,
            backgroundTaskManager: dependencies.backgroundTaskManager
        )
    }

    var preferredColorScheme: ColorScheme? {
        guard !state.appSettings.useSystemColorScheme else { return nil }
        return state.appSettings.prefersDarkMode ? .dark : .light
    }

    var chromeTint: Color {
        Color(hex: "#2F6BFF")
    }

    private func seedInitialLibraryIfNeeded() {
        guard state.library.isEmpty else { return }
    }

    func persist() {
        state.schemaVersion = PersistedState.currentSchemaVersion
        state.sourceRepos = repoRecords.map(\.url)
        let snapshot = DatabaseSnapshot(
            state: state,
            imports: importRecords,
            importJobs: importJobsState,
            repoRecords: repoRecords,
            diagnostics: diagnosticLogs,
            downloadedChapters: persistedDownloadedChapters()
        )
        databaseCoordinator.saveSnapshot(snapshot)
        legacyStore.save(state)
    }

    func rebuildSourceRepository() {
        repository = RuntimeSourceRepository(repoRecords: repoRecords, cache: cacheController)
        sources = repository.sources()
    }

    func appendDiagnostic(kind: DiagnosticLogKind, title: String, message: String, metadata: [String: String]) {
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

    func refreshCacheStats() async {
        cacheStats = await cacheController.stats()
    }

    var downloadsDirectoryURL: URL {
        databaseCoordinator.downloadsDirectoryURL
    }

    func cachedSourceManga(for sourceID: String) -> [Manga]? {
        sourceMangaRuntimeCache.value(forKey: sourceID)
    }

    func setCachedSourceManga(_ manga: [Manga], for sourceID: String) {
        sourceMangaRuntimeCache.setValue(manga, forKey: sourceID)
        sourceMangaCache = sourceMangaRuntimeCache.snapshot()
    }

    func removeCachedSourceManga(for sourceID: String) {
        sourceMangaRuntimeCache.removeValue(forKey: sourceID)
        sourceMangaCache = sourceMangaRuntimeCache.snapshot()
    }

    func clearCachedSourceManga() {
        sourceMangaRuntimeCache.removeAll()
        sourceMangaCache = [:]
    }

    func cachedGenreTags(for sourceID: String) -> [GenreTag]? {
        sourceGenreRuntimeCache.value(forKey: sourceID)
    }

    func setCachedGenreTags(_ genres: [GenreTag], for sourceID: String) {
        sourceGenreRuntimeCache.setValue(genres, forKey: sourceID)
        sourceGenreCache = sourceGenreRuntimeCache.snapshot()
    }

    func clearCachedGenreTags() {
        sourceGenreRuntimeCache.removeAll()
        sourceGenreCache = [:]
    }

    func cachedChapters(for mangaID: String) -> [Chapter]? {
        chapterRuntimeCache.value(forKey: mangaID)
    }

    func peekCachedChapters(for mangaID: String) -> [Chapter]? {
        chapterRuntimeCache.peekValue(forKey: mangaID)
    }

    func setCachedChapters(_ chapters: [Chapter], for mangaID: String) {
        chapterRuntimeCache.setValue(chapters, forKey: mangaID)
        chapterCache = chapterRuntimeCache.snapshot()
    }

    func removeCachedChapters(for mangaID: String) {
        chapterRuntimeCache.removeValue(forKey: mangaID)
        chapterCache = chapterRuntimeCache.snapshot()
    }

    func clearCachedChapters(preservingOfflineOnly: Bool) {
        if preservingOfflineOnly {
            let offline = chapterRuntimeCache.snapshot().reduce(into: [String: [Chapter]]()) { partialResult, pair in
                let chapters = pair.value.filter { $0.isDownloaded || !$0.pages.isEmpty }
                if !chapters.isEmpty {
                    partialResult[pair.key] = chapters
                }
            }
            chapterRuntimeCache.removeAll()
            for (key, chapters) in offline {
                chapterRuntimeCache.setValue(chapters, forKey: key)
            }
        } else {
            chapterRuntimeCache.removeAll()
        }
        chapterCache = chapterRuntimeCache.snapshot()
    }

    func cachedPages(for chapterID: String) -> [ReaderPage]? {
        pageRuntimeCache.value(forKey: chapterID)
    }

    func setCachedPages(_ pages: [ReaderPage], for chapterID: String) {
        pageRuntimeCache.setValue(pages, forKey: chapterID)
        pageCache = pageRuntimeCache.snapshot()
    }

    func removeCachedPages(for chapterID: String) {
        pageRuntimeCache.removeValue(forKey: chapterID)
        pageCache = pageRuntimeCache.snapshot()
    }

    func clearCachedPages() {
        pageRuntimeCache.removeAll()
        pageCache = [:]
    }

    func trimRuntimeCaches(fraction: Double) {
        let offlineChapters = persistedDownloadedChapters()
        sourceMangaRuntimeCache.trimToFraction(fraction)
        sourceGenreRuntimeCache.trimToFraction(fraction)
        chapterRuntimeCache.removeAll()
        for (key, chapters) in offlineChapters {
            chapterRuntimeCache.setValue(chapters, forKey: key)
        }
        pageRuntimeCache.trimToFraction(fraction)
        sourceMangaCache = sourceMangaRuntimeCache.snapshot()
        sourceGenreCache = sourceGenreRuntimeCache.snapshot()
        chapterCache = chapterRuntimeCache.snapshot()
        pageCache = pageRuntimeCache.snapshot()
    }

    func reconfigureRuntimeCaches(
        sourceMangaLimit: Int,
        sourceGenreLimit: Int,
        chapterLimit: Int,
        pageLimit: Int
    ) {
        let offlineChapterCount = persistedDownloadedChapters().count
        sourceMangaRuntimeCache.countLimit = sourceMangaLimit
        sourceGenreRuntimeCache.countLimit = sourceGenreLimit
        chapterRuntimeCache.countLimit = max(chapterLimit, offlineChapterCount)
        pageRuntimeCache.countLimit = pageLimit
        sourceMangaCache = sourceMangaRuntimeCache.snapshot()
        sourceGenreCache = sourceGenreRuntimeCache.snapshot()
        chapterCache = chapterRuntimeCache.snapshot()
        pageCache = pageRuntimeCache.snapshot()
    }

    private func persistedDownloadedChapters() -> [String: [Chapter]] {
        chapterRuntimeCache.snapshot().reduce(into: [:]) { partialResult, pair in
            let offline = pair.value.filter { $0.isDownloaded || !$0.pages.isEmpty }
            if !offline.isEmpty {
                partialResult[pair.key] = offline
            }
        }
    }
}
