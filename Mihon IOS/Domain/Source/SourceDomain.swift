//
//  SourceDomain.swift
//  Mihon IOS
//

import Foundation

enum SourceKind: String, Codable, CaseIterable, Hashable {
    case remote
    case local
}

enum SourceEngineFamily: String, Codable, CaseIterable, Hashable, Identifiable {
    case internalCatalog
    case local
    case natsuId
    case madara
    case mangaThemesia
    case mangaBox
    case asuraScans
    case komikIndoID
    case zeistManga
    case fmReader
    case foolSlide
    case newToki
    case customParsed
    case api
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .internalCatalog: return "Internal Catalog"
        case .local: return "Local Files"
        case .natsuId: return "NatsuId"
        case .madara: return "Madara"
        case .mangaThemesia: return "MangaThemesia"
        case .mangaBox: return "MangaBox"
        case .asuraScans: return "Asura Scans"
        case .komikIndoID: return "KomikIndoID"
        case .zeistManga: return "ZeistManga"
        case .fmReader: return "FMReader"
        case .foolSlide: return "FoolSlide"
        case .newToki: return "NewToki"
        case .customParsed: return "Custom Http/Parsed"
        case .api: return "API"
        case .unknown: return "Unknown"
        }
    }
}

enum SourceCapability: String, Codable, CaseIterable, Hashable, Identifiable {
    case popular
    case latest
    case search
    case mangaDetail
    case chapterList
    case pageList
    case filters
    case preferences
    case reader

    var id: String { rawValue }
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
    let engineFamily: SourceEngineFamily
    let summary: String
    let systemImage: String
    let language: SourceLanguage
    let isEnabled: Bool
    let isPinned: Bool
    let allowsAdultContent: Bool
}

enum SourceAuthMode: String, Codable, Hashable {
    case none
    case webSession
    case cookies
    case unsupported
}

struct SourceRequestPolicy: Codable, Hashable {
    let rateLimit: Int
    let referrer: String?
    let userAgent: String?
    let requiresCookies: Bool
}

struct SourceRuntimeContext: Codable, Hashable {
    let baseURL: String
    let language: SourceLanguage
    let authMode: SourceAuthMode
    let requestPolicy: SourceRequestPolicy
}

struct SourceFilterSchema: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let kind: String
}

struct SourcePreferenceSchema: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let detail: String
}

struct SourceDescriptor: Identifiable, Codable, Hashable {
    let id: String
    let sourceID: String
    let name: String
    let engineFamily: SourceEngineFamily
    let kind: SourceKind
    let language: SourceLanguage
    let baseURL: String?
    let capabilities: Set<SourceCapability>
    let featureFlags: [String]
    let overrides: [String: String]
    let context: SourceRuntimeContext?
    let filterSchema: [SourceFilterSchema]
    let preferenceSchema: [SourcePreferenceSchema]
    let packageName: String?
    let version: String?
    let languageCode: String?
    let origin: String?
    let supportStatus: SourceSupportStatus
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
    let languageCodes: [String]
    let sources: [Source]
    let originLabel: String
    let supportStatus: SourceSupportStatus
}

enum SourceSupportStatus: String, Codable, CaseIterable, Hashable, Identifiable {
    case live
    case planned
    case unsupported

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: return "Live"
        case .planned: return "Planned"
        case .unsupported: return "Unsupported"
        }
    }
}

struct SourceClassificationResult: Codable, Hashable {
    let engineFamily: SourceEngineFamily
    let supportStatus: SourceSupportStatus
    let featureFlags: [String]
    let overrides: [String: String]
    let reason: String
}

struct ImportedSourceDescriptor: Identifiable, Codable, Hashable {
    let id: String
    let sourceID: String
    let name: String
    let language: SourceLanguage
    let languageCode: String
    let baseURL: String
    let packageName: String
    let version: String
    let allowsAdultContent: Bool
    let apkURL: String?
    let engineFamily: SourceEngineFamily
    let supportStatus: SourceSupportStatus
    let capabilities: Set<SourceCapability>
    let featureFlags: [String]
    let overrides: [String: String]
    let origin: String
    let summary: String
}

struct SourceRepoPackage: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let packageName: String
    let apkURL: String?
    let languageCode: String
    let version: String
    let allowsAdultContent: Bool
    let sources: [ImportedSourceDescriptor]
}

struct SourceRepoRecord: Identifiable, Codable, Hashable {
    let id: String
    let url: String
    let title: String
    let fetchedAt: Date
    let packages: [SourceRepoPackage]
    let importedSources: [ImportedSourceDescriptor]
    let lastError: String?
}

enum SourceRepoImportError: String, Codable, Hashable, Error {
    case invalidURL
    case unreadablePayload
    case invalidPayload
}

extension SourceRepoImportError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The repository URL is not valid."
        case .unreadablePayload:
            return "The repository could not be downloaded."
        case .invalidPayload:
            return "The repository JSON format is not supported by the current importer."
        }
    }
}

struct SourcePreference: Identifiable, Hashable {
    let id: String
    let title: String
    let value: String
}

