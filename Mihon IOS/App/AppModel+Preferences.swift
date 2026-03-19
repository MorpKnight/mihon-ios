//
//  AppModel+Preferences.swift
//  Mihon IOS
//

import Foundation

extension AppModel {
    var currentLanguageLabel: String {
        state.appSettings.appLanguageCode == "system" ? "System Default" : state.appSettings.appLanguageCode.uppercased()
    }

    func markOnboardingCompleted() {
        state.onboardingCompleted = true
        persist()
    }

    func resetOnboarding() {
        state.onboardingCompleted = false
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
        state.securityPreferences.requireBiometricUnlock = Self.biometricLockFeatureEnabled ? enabled : false
        isAppUnlocked = true
        biometricErrorMessage = Self.biometricLockFeatureEnabled ? biometricErrorMessage : nil
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

    func setMemoryCacheLimitMB(_ mb: Int) {
        state.advancedPreferences.memoryCacheLimitMB = min(max(mb, 20), 200)
        persist()
        Task { await applyCacheConfiguration() }
    }

    func setImageCacheCountLimit(_ count: Int) {
        state.advancedPreferences.imageCacheCountLimit = min(max(count, 40), 200)
        persist()
        Task { await applyCacheConfiguration() }
    }

    func applyCacheConfiguration() async {
        let prefs = state.advancedPreferences
        let runtimeSourceLimit = max(12, prefs.imageCacheCountLimit / 3)
        let runtimeGenreLimit = max(8, runtimeSourceLimit / 2)
        let runtimeChapterLimit = max(20, prefs.imageCacheCountLimit / 2)
        let runtimePageLimit = max(20, prefs.imageCacheCountLimit)

        let config = CacheConfiguration(
            imageCountLimit: prefs.imageCacheCountLimit,
            imageBytesLimit: prefs.memoryCacheLimitMB * 1_024 * 1_024,
            dataCountLimit: CacheConfiguration.default.dataCountLimit,
            dataBytesLimit: max(20, prefs.memoryCacheLimitMB / 2) * 1_024 * 1_024,
            diskImageBytesLimit: CacheConfiguration.default.diskImageBytesLimit,
            diskMetadataBytesLimit: CacheConfiguration.default.diskMetadataBytesLimit,
            diskNetworkBytesLimit: CacheConfiguration.default.diskNetworkBytesLimit
        )
        reconfigureRuntimeCaches(
            sourceMangaLimit: runtimeSourceLimit,
            sourceGenreLimit: runtimeGenreLimit,
            chapterLimit: runtimeChapterLimit,
            pageLimit: runtimePageLimit
        )
        await cacheController.reconfigure(config)
    }
}
