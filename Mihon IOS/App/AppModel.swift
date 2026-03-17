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

    var repository: SourceRepository
    let importRepository: FileImportRepository
    let localContentRepository: LocalContentRepository
    let readerAssetRepository: ReaderAssetRepository
    let repoImporter: SourceRepoImporter
    let cacheController: AppCacheManaging

    var downloadActiveJobID: UUID?
    var downloadActiveTask: Task<Void, Never>?

    init(
        store: AppStateStore = AppStateStore(),
        repository: SourceRepository? = nil,
        databaseCoordinator: FileDatabaseCoordinator? = nil,
        localContentRepository: LocalContentRepository = DefaultLocalContentRepository(),
        readerAssetRepository: ReaderAssetRepository = DefaultReaderAssetRepository(),
        repoImporter: SourceRepoImporter = SourceRepoImporter(),
        cacheController: AppCacheManaging = AppCacheController.shared
    ) {
        self.legacyStore = store
        self.databaseCoordinator = databaseCoordinator ?? FileDatabaseCoordinator(stateStore: store)
        self.localContentRepository = localContentRepository
        self.readerAssetRepository = readerAssetRepository
        self.repoImporter = repoImporter
        self.cacheController = cacheController
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
        self.repository = repository ?? RuntimeSourceRepository(repoRecords: hydratedRepoRecords, cache: cacheController)
        var persistedState = snapshot.state
        persistedState.sourceRepos = hydratedRepoRecords.map(\.url)
        self.state = persistedState
        self.importRecords = snapshot.imports
        self.importJobsState = snapshot.importJobs
        self.repoRecords = hydratedRepoRecords
        self.sourceMangaCache = snapshot.cachedManga
        self.sourceGenreCache = [:]
        self.chapterCache = snapshot.cachedChapters
        self.pageCache = [:]
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
            cachedManga: sourceMangaCache,
            cachedChapters: chapterCache
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
}
