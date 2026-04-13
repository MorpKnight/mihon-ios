//
//  DiagnosticsDomain.swift
//  Mihon IOS
//

import Foundation

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
    case cache
    case stateTransition

    var id: String { rawValue }
}

enum DiagnosticSeverity: String, Codable, CaseIterable, Hashable, Identifiable {
    case info
    case warning
    case error
    case critical

    var id: String { rawValue }
}

enum DiagnosticErrorCode: String, Codable, Hashable {
    case appLocalImportFailed = "APP_LOCAL_IMPORT_FAILED"
    case appLocalImportBatchFailed = "APP_LOCAL_IMPORT_BATCH_FAILED"
    case secBiometricUnlockFailed = "SEC_BIOMETRIC_UNLOCK_FAILED"
    case dlCancelled = "DL_CANCELLED"
    case dlFailed = "DL_FAILED"
    case repoImported = "REPO_IMPORTED"
    case repoImportFailed = "REPO_IMPORT_FAILED"
    case repoRefreshed = "REPO_REFRESHED"
    case repoRefreshFailed = "REPO_REFRESH_FAILED"
    case repoRemoved = "REPO_REMOVED"
    case cacheMetadataCleared = "CACHE_METADATA_CLEARED"
    case cacheAllCleared = "CACHE_ALL_CLEARED"
    case cacheMemoryPressureTrim = "CACHE_MEMORY_PRESSURE_TRIM"
    case srcFeedFailed = "SRC_FEED_FAILED"
    case srcGenreLoadFailed = "SRC_GENRE_LOAD_FAILED"
    case srcMangaDetailFailed = "SRC_MANGA_DETAIL_FAILED"
    case srcChapterOrderNormalized = "SRC_CHAPTER_ORDER_NORMALIZED"
    case srcChapterLoadFailed = "SRC_CHAPTER_LOAD_FAILED"
    case rdrPageLoadWarning = "RDR_PAGE_LOAD_WARNING"
    case rdrPageLoadFailed = "RDR_PAGE_LOAD_FAILED"
    case rdrRemoteImageFailed = "RDR_REMOTE_IMAGE_FAILED"
    case rdrLocalAssetMissing = "RDR_LOCAL_ASSET_MISSING"
    case rdrLocalFileNotFound = "RDR_LOCAL_FILE_NOT_FOUND"
    case rdrLocalDecodeFailed = "RDR_LOCAL_DECODE_FAILED"
    case rdrTapNavigationBlocked = "RDR_TAP_NAVIGATION_BLOCKED"
    case rdrVerticalTransitionCommitted = "RDR_VERTICAL_TRANSITION_COMMITTED"
    case rdrVerticalTransitionCancelled = "RDR_VERTICAL_TRANSITION_CANCELLED"
    case rdrTransitionBlocked = "RDR_TRANSITION_BLOCKED"
    case rdrTransitionStarted = "RDR_TRANSITION_STARTED"
    case rdrInvalidChapter = "RDR_INVALID_CHAPTER"
}

struct DiagnosticLogEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    let kind: DiagnosticLogKind
    let severity: DiagnosticSeverity
    let title: String
    let message: String
    let errorCode: String?
    let module: String?
    let resolutionHint: String?
    let metadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case kind
        case severity
        case title
        case message
        case errorCode
        case module
        case resolutionHint
        case metadata
    }

    init(
        id: UUID,
        timestamp: Date,
        kind: DiagnosticLogKind,
        severity: DiagnosticSeverity = .error,
        title: String,
        message: String,
        errorCode: String? = nil,
        module: String? = nil,
        resolutionHint: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.severity = severity
        self.title = title
        self.message = message
        self.errorCode = errorCode
        self.module = module
        self.resolutionHint = resolutionHint
        self.metadata = metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? .distantPast
        kind = try container.decodeIfPresent(DiagnosticLogKind.self, forKey: .kind) ?? .app
        severity = try container.decodeIfPresent(DiagnosticSeverity.self, forKey: .severity) ?? .error
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Unknown Diagnostic"
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        errorCode = try container.decodeIfPresent(String.self, forKey: .errorCode)
        module = try container.decodeIfPresent(String.self, forKey: .module)
        resolutionHint = try container.decodeIfPresent(String.self, forKey: .resolutionHint)
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }
}

