//
//  PersistedState.swift
//  Mihon IOS
//

import Foundation

struct PersistedState: Codable, Hashable {
    static let currentSchemaVersion = 5

    var schemaVersion: Int
    var categories: [Category]
    var library: [LibraryEntry]
    var progress: [ReadingProgress]
    var history: [HistoryEntry]
    // Tracks last "seen" chapter per manga for Updates tab unread badge.
    // If missing for a given mangaID, updates are considered unread.
    var updatesLastSeenChapterIDByMangaID: [String: String]
    var readerPreferences: ReaderPreferences
    var libraryPreferences: LibraryPreferences
    var appSettings: AppSettings
    var downloadPreferences: DownloadPreferences
    var browsePreferences: BrowsePreferences
    var securityPreferences: SecurityPreferences
    var advancedPreferences: AdvancedPreferences
    var trackers: [TrackerBinding]
    var mangaNotes: [String: String]
    var onboardingCompleted: Bool
    var sourceRepos: [String]
    var persistedMangas: [Manga] // Added

    static let `default` = PersistedState(
        schemaVersion: currentSchemaVersion,
        categories: [
            Category(id: "reading", name: "Reading", systemImage: "books.vertical"),
            Category(id: "favorites", name: "Favorites", systemImage: "heart"),
            Category(id: "downloaded", name: "Downloaded", systemImage: "arrow.down.circle"),
        ],
        library: [],
        progress: [],
        history: [],
        updatesLastSeenChapterIDByMangaID: [:],
        readerPreferences: ReaderPreferences(
            mode: .pagerDefault,
            keepAwake: true,
            orientation: .system,
            showPageNumber: true,
            colorFilter: ReaderColorFilter(enabled: false, grayscale: 0, dimming: 0)
        ),
        libraryPreferences: LibraryPreferences(
            showContinueReading: true,
            defaultCategoryID: "reading",
            showDownloadedBadge: true,
            showUnreadBadge: true,
            sortMode: .recent
        ),
        appSettings: AppSettings(
            useSystemColorScheme: true,
            prefersDarkMode: false,
            downloadedOnly: false,
            incognitoMode: false,
            appLanguageCode: "system",
            releaseNotesSeenVersion: "" // Added
        ),
        downloadPreferences: DownloadPreferences(
            wifiOnly: true,
            autoDownloadNewChapters: false,
            unreadOnly: true,
            queueStrategy: .sequential
        ),
        browsePreferences: BrowsePreferences(
            enabledLanguages: Set(SourceLanguage.allCases),
            hideAdultSources: true,
            enabledSourcesOnly: false,
            pinnedSourcesOnly: false
        ),
        securityPreferences: SecurityPreferences(
            blurAppSwitcher: true,
            lockLibraryEdits: false,
            hideSensitiveCovers: false,
            requireBiometricUnlock: false
        ),
        advancedPreferences: AdvancedPreferences(
            imagePrefetchCount: 2,
            historyLimit: 80,
            showDiagnostics: false,
            aggressiveImageRetry: true,
            memoryCacheLimitMB: 80,
            imageCacheCountLimit: 100
        ),
        trackers: [],
        mangaNotes: [:],
        onboardingCompleted: false,
        sourceRepos: ["https://repo.mihon.app/index.json"],
        persistedMangas: [] // Added
    )

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case categories
        case library
        case progress
        case history
        case updatesLastSeenChapterIDByMangaID // Added
        case readerPreferences
        case libraryPreferences
        case appSettings
        case downloadPreferences
        case browsePreferences
        case securityPreferences
        case advancedPreferences
        case trackers
        case mangaNotes
        case onboardingCompleted
        case sourceRepos
        case persistedMangas // Added
    }

    init(
        schemaVersion: Int,
        categories: [Category],
        library: [LibraryEntry],
        progress: [ReadingProgress],
        history: [HistoryEntry],
        updatesLastSeenChapterIDByMangaID: [String: String],
        readerPreferences: ReaderPreferences,
        libraryPreferences: LibraryPreferences,
        appSettings: AppSettings,
        downloadPreferences: DownloadPreferences,
        browsePreferences: BrowsePreferences,
        securityPreferences: SecurityPreferences,
        advancedPreferences: AdvancedPreferences,
        trackers: [TrackerBinding],
        mangaNotes: [String: String],
        onboardingCompleted: Bool,
        sourceRepos: [String],
        persistedMangas: [Manga] // Added
    ) {
        self.schemaVersion = schemaVersion
        self.categories = categories
        self.library = library
        self.progress = progress
        self.history = history
        self.updatesLastSeenChapterIDByMangaID = updatesLastSeenChapterIDByMangaID
        self.readerPreferences = readerPreferences
        self.libraryPreferences = libraryPreferences
        self.appSettings = appSettings
        self.downloadPreferences = downloadPreferences
        self.browsePreferences = browsePreferences
        self.securityPreferences = securityPreferences
        self.advancedPreferences = advancedPreferences
        self.trackers = trackers
        self.mangaNotes = mangaNotes
        self.onboardingCompleted = onboardingCompleted
        self.sourceRepos = sourceRepos
        self.persistedMangas = persistedMangas // Added
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = PersistedState.default

        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        categories = try container.decodeIfPresent([Category].self, forKey: .categories) ?? defaults.categories
        library = try container.decodeIfPresent([LibraryEntry].self, forKey: .library) ?? []
        progress = try container.decodeIfPresent([ReadingProgress].self, forKey: .progress) ?? []
        history = try container.decodeIfPresent([HistoryEntry].self, forKey: .history) ?? []
        updatesLastSeenChapterIDByMangaID = try container.decodeIfPresent([String: String].self, forKey: .updatesLastSeenChapterIDByMangaID) ?? [:]
        readerPreferences = try container.decodeIfPresent(ReaderPreferences.self, forKey: .readerPreferences) ?? defaults.readerPreferences
        libraryPreferences = try container.decodeIfPresent(LibraryPreferences.self, forKey: .libraryPreferences) ?? defaults.libraryPreferences
        appSettings = try container.decodeIfPresent(AppSettings.self, forKey: .appSettings) ?? defaults.appSettings
        downloadPreferences = try container.decodeIfPresent(DownloadPreferences.self, forKey: .downloadPreferences) ?? defaults.downloadPreferences
        browsePreferences = try container.decodeIfPresent(BrowsePreferences.self, forKey: .browsePreferences) ?? defaults.browsePreferences
        securityPreferences = try container.decodeIfPresent(SecurityPreferences.self, forKey: .securityPreferences) ?? defaults.securityPreferences
        advancedPreferences = try container.decodeIfPresent(AdvancedPreferences.self, forKey: .advancedPreferences) ?? defaults.advancedPreferences
        trackers = try container.decodeIfPresent([TrackerBinding].self, forKey: .trackers) ?? []
        mangaNotes = try container.decodeIfPresent([String: String].self, forKey: .mangaNotes) ?? [:]
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        sourceRepos = try container.decodeIfPresent([String].self, forKey: .sourceRepos) ?? defaults.sourceRepos
        persistedMangas = try container.decodeIfPresent([Manga].self, forKey: .persistedMangas) ?? [] // Added
    }
}
