//
//  MihonDomain.swift
//  Mihon IOS
//

import Foundation

enum SourceKind: String, Codable, CaseIterable, Hashable {
    case remote
    case local
}

enum SourceLanguage: String, Codable, CaseIterable, Identifiable, Hashable {
    case english = "English"
    case indonesian = "Indonesian"
    case japanese = "Japanese"
    case multi = "Multi"

    var id: String { rawValue }
}

struct Source: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let kind: SourceKind
    let summary: String
    let systemImage: String
    let language: SourceLanguage
    let isEnabled: Bool
    let isPinned: Bool
    let allowsAdultContent: Bool
}

struct SourceSearchRequest: Hashable {
    var query: String
    var page: Int
    var filters: [SourceFilterValue]
}

enum SourceFeedKind: String, CaseIterable, Identifiable, Hashable {
    case popular
    case latest
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .popular: return "Popular"
        case .latest: return "Latest"
        case .search: return "Search"
        }
    }
}

enum SourceFilterValue: Hashable {
    case sort(String)
    case orderAscending(Bool)
    case types([String])
    case genreInclude(mode: String, slugs: [String])
    case genreExclude(mode: String, slugs: [String])
}

struct GenreTag: Identifiable, Codable, Hashable {
    var id: String { slug }
    let name: String
    let slug: String
}

struct NatsuIdSourceConfiguration: Hashable {
    let source: Source
    let baseURL: String
    let rateLimit: Int
    let chapterListPageOverride: Int?
}

typealias KiryuuSourceConfiguration = NatsuIdSourceConfiguration

protocol SourceRuntime {
    var source: Source { get }

    func popularManga(page: Int) async throws -> [Manga]
    func latestManga(page: Int) async throws -> [Manga]
    func searchManga(_ request: SourceSearchRequest) async throws -> [Manga]
    func mangaDetails(mangaIDOrURL: String) async throws -> SourceMangaDetails
    func chapters(for manga: Manga) async throws -> SourceChapterDetails
    func pages(for chapter: Chapter) async throws -> SourcePageAsset
    func genreTags() async throws -> [GenreTag]
}

protocol SourceCatalogRuntime {
    func activeSources() -> [Source]
}

struct SourceCatalogItem: Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let version: String
    let isInstalled: Bool
    let hasUpdate: Bool
    let isTrusted: Bool
    let languages: [SourceLanguage]
    let sources: [Source]
}

struct SourcePreference: Identifiable, Hashable {
    let id: String
    let title: String
    let value: String
}

enum ReaderAssetKind: String, Codable, Hashable {
    case text
    case image
}

struct ReaderPage: Identifiable, Codable, Hashable {
    let id: String
    let index: Int
    let title: String
    let body: String
    let accentHex: String
    let assetKind: ReaderAssetKind
    let assetPath: String?
    let remoteURL: String?
}

struct Chapter: Identifiable, Codable, Hashable {
    let id: String
    let mangaID: String
    let title: String
    let number: Double
    let releaseDate: Date
    let isDownloaded: Bool
    let pages: [ReaderPage]
}

struct Manga: Identifiable, Codable, Hashable {
    let id: String
    let sourceID: String
    let title: String
    let author: String
    let summary: String
    let genres: [String]
    let coverHexes: [String]
    let coverURL: String?
    let statusText: String
}

struct SourceMangaDetails: Identifiable, Hashable {
    var id: String { manga.id }
    let manga: Manga
}

struct SourceChapterDetails: Hashable {
    let chapters: [Chapter]
}

struct SourcePageAsset: Hashable {
    let pages: [ReaderPage]
    let errorMessage: String?
}

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

enum TrackerService: String, Codable, CaseIterable, Identifiable {
    case anilist = "AniList"
    case myAnimeList = "MyAnimeList"
    case kitsu = "Kitsu"
    case mangaUpdates = "MangaUpdates"
    case shikimori = "Shikimori"
    case bangumi = "Bangumi"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .anilist: return "chart.line.text.clipboard"
        case .myAnimeList: return "list.star"
        case .kitsu: return "checklist.checked"
        case .mangaUpdates: return "clock.badge.checkmark"
        case .shikimori: return "sparkles.tv"
        case .bangumi: return "person.3.sequence"
        }
    }
}

struct TrackerBinding: Identifiable, Codable, Hashable {
    let id: UUID
    let mangaID: String
    let service: TrackerService
    var remoteTitle: String
    var status: String
    var progressText: String
    var score: String
}

enum DownloadState: String, Hashable {
    case queued
    case downloading
    case paused
    case complete
    case failed
}

struct DownloadJob: Identifiable, Hashable {
    let id: UUID
    let manga: Manga
    let chapter: Chapter
    var progress: Double
    var state: DownloadState
}

struct BackupPayload: Identifiable, Hashable {
    let id: UUID
    let createdAt: Date
    let sections: [String]
    let itemCount: Int
}

struct MigrationCandidate: Identifiable, Hashable {
    let id: String
    let source: Source
    let manga: Manga
}

enum ImportKind: String, Codable, CaseIterable, Hashable {
    case folder
    case image
    case cbz
    case zip
    case epub
    case unsupported
}

enum ImportStatus: String, Codable, CaseIterable, Hashable {
    case ready
    case pendingExtraction
    case failed
}

struct ImportedAsset: Identifiable, Codable, Hashable {
    let id: String
    let chapterID: String
    let orderIndex: Int
    let kind: ReaderAssetKind
    let filePath: String?
    let textBody: String?
    let accentHex: String
}

struct ImportedChapter: Identifiable, Codable, Hashable {
    let id: String
    let titleID: String
    let title: String
    let orderIndex: Int
    let assetIDs: [String]
    let importedAt: Date
}

struct ImportedTitle: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let author: String
    let summary: String
    let sourceID: String
    let coverPath: String?
    let originalPath: String
    let kind: ImportKind
    let importedAt: Date
    let chapterIDs: [String]
}

struct ImportRecord: Identifiable, Codable, Hashable {
    let id: String
    let title: ImportedTitle
    let chapters: [ImportedChapter]
    let assets: [ImportedAsset]
}

struct ImportJob: Identifiable, Codable, Hashable {
    let id: UUID
    let fileName: String
    let kind: ImportKind
    var status: ImportStatus
    let createdAt: Date
    let importedTitleID: String?
    let detail: String
}

struct ReaderSession: Identifiable, Codable, Hashable {
    var id: String { mangaID }
    let mangaID: String
    var chapterID: String
    var pageIndex: Int
    var updatedAt: Date
}

enum DiagnosticLogKind: String, Codable, CaseIterable, Hashable, Identifiable {
    case app
    case repo
    case source
    case reader
    case security

    var id: String { rawValue }
}

struct DiagnosticLogEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    let kind: DiagnosticLogKind
    let title: String
    let message: String
    let metadata: [String: String]
}

enum LibraryRoute: Hashable {
    case mangaDetail(Manga)
    case reader(Manga, Chapter)
    case categoryManager
    case librarySettings
    case batchMigration
}

enum BrowseRoute: Hashable {
    case source(Source)
    case mangaDetail(Manga)
    case globalSearch
    case sourceCatalog
    case sourceCatalogDetail(SourceCatalogItem)
    case sourcePreferences(Source)
    case sourceRepos
    case sourceFilters
    case migrationSources
}

enum HistoryRoute: Hashable {
    case mangaDetail(Manga)
    case reader(Manga, Chapter)
}

enum UpdatesRoute: Hashable {
    case mangaDetail(Manga)
}

enum MoreRoute: Hashable {
    case downloadQueue
    case stats
    case settings
    case dataStorage
    case categories
    case about
    case backupCreate
    case backupRestore
    case tracking
}

struct PersistedState: Codable, Hashable {
    static let currentSchemaVersion = 4

    var schemaVersion: Int
    var categories: [Category]
    var library: [LibraryEntry]
    var progress: [ReadingProgress]
    var history: [HistoryEntry]
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
            appLanguageCode: "system"
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
            aggressiveImageRetry: true
        ),
        trackers: [],
        mangaNotes: [:],
        onboardingCompleted: false,
        sourceRepos: ["https://repo.mihon.app/index.json"]
    )

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case categories
        case library
        case progress
        case history
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
    }

    init(
        schemaVersion: Int,
        categories: [Category],
        library: [LibraryEntry],
        progress: [ReadingProgress],
        history: [HistoryEntry],
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
        sourceRepos: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.categories = categories
        self.library = library
        self.progress = progress
        self.history = history
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
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = PersistedState.default

        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        categories = try container.decodeIfPresent([Category].self, forKey: .categories) ?? defaults.categories
        library = try container.decodeIfPresent([LibraryEntry].self, forKey: .library) ?? []
        progress = try container.decodeIfPresent([ReadingProgress].self, forKey: .progress) ?? []
        history = try container.decodeIfPresent([HistoryEntry].self, forKey: .history) ?? []
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
    }
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
