//
//  PreferencesDomain.swift
//  Mihon IOS
//

import Foundation

enum ReaderMode: String, Codable, CaseIterable, Identifiable {
    case pagerDefault
    case pagerLTR
    case pagerRTL
    case vertical
    case webtoon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pagerDefault: return "Paged"
        case .pagerLTR: return "Paged LTR"
        case .pagerRTL: return "Paged RTL"
        case .vertical: return "Vertical"
        case .webtoon: return "Webtoon"
        }
    }
}

enum ReaderOrientation: String, Codable, CaseIterable, Identifiable {
    case system
    case portrait
    case landscape

    var id: String { rawValue }
}

struct ReaderColorFilter: Codable, Hashable {
    var enabled: Bool
    var grayscale: Double
    var dimming: Double
}

struct ReaderPreferences: Codable, Hashable {
    var mode: ReaderMode
    var keepAwake: Bool
    var orientation: ReaderOrientation
    var showPageNumber: Bool
    var colorFilter: ReaderColorFilter
}

struct LibraryPreferences: Codable, Hashable {
    var showContinueReading: Bool
    var defaultCategoryID: String
    var showDownloadedBadge: Bool
    var showUnreadBadge: Bool
    var sortMode: LibrarySortMode
}

struct AppSettings: Codable, Hashable {
    var useSystemColorScheme: Bool
    var prefersDarkMode: Bool
    var downloadedOnly: Bool
    var incognitoMode: Bool
    var appLanguageCode: String
    var releaseNotesSeenVersion: String
}

enum DownloadQueueStrategy: String, Codable, CaseIterable, Identifiable {
    case sequential
    case groupedByTitle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sequential: return "Sequential"
        case .groupedByTitle: return "Grouped by Title"
        }
    }
}

struct DownloadPreferences: Codable, Hashable {
    var wifiOnly: Bool
    var autoDownloadNewChapters: Bool
    var unreadOnly: Bool
    var queueStrategy: DownloadQueueStrategy
}

struct BrowsePreferences: Codable, Hashable {
    var enabledLanguages: Set<SourceLanguage>
    var hideAdultSources: Bool
    var enabledSourcesOnly: Bool
    var pinnedSourcesOnly: Bool
}

struct SecurityPreferences: Codable, Hashable {
    var blurAppSwitcher: Bool
    var lockLibraryEdits: Bool
    var hideSensitiveCovers: Bool
    var requireBiometricUnlock: Bool
}

struct AdvancedPreferences: Codable, Hashable {
    var imagePrefetchCount: Int
    var historyLimit: Int
    var showDiagnostics: Bool
    var aggressiveImageRetry: Bool
    var memoryCacheLimitMB: Int
    var imageCacheCountLimit: Int

    init(
        imagePrefetchCount: Int = 2,
        historyLimit: Int = 100,
        showDiagnostics: Bool = false,
        aggressiveImageRetry: Bool = false,
        memoryCacheLimitMB: Int = 80,
        imageCacheCountLimit: Int = 100
    ) {
        self.imagePrefetchCount = imagePrefetchCount
        self.historyLimit = historyLimit
        self.showDiagnostics = showDiagnostics
        self.aggressiveImageRetry = aggressiveImageRetry
        self.memoryCacheLimitMB = memoryCacheLimitMB
        self.imageCacheCountLimit = imageCacheCountLimit
    }
}

struct AppPreferences: Hashable {
    var reader: ReaderPreferences
    var library: LibraryPreferences
    var app: AppSettings
    var downloads: DownloadPreferences
    var browse: BrowsePreferences
    var security: SecurityPreferences
    var advanced: AdvancedPreferences
}

