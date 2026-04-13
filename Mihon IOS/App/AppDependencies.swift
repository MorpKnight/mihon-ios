//
//  AppDependencies.swift
//  Mihon IOS
//

import Foundation

/// Lightweight dependency container used to assemble `AppModel`.
/// Keeps composition in one place and makes future test wiring simpler.
@MainActor
struct AppDependencies {
    var store: AppStateStore
    var repository: SourceRepository?
    var databaseCoordinator: FileDatabaseCoordinator?
    var localContentRepository: LocalContentRepository
    var readerAssetRepository: ReaderAssetRepository
    var repoImporter: SourceRepoImporter
    var cacheController: AppCacheManaging
    var biometricAuthenticator: BiometricAuthenticating
    var downloadsService: DownloadsServicing
    var downloadQueueCoordinator: DownloadQueueCoordinating
    var backgroundTaskManager: BackgroundTaskManaging

    static let live = AppDependencies(
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
