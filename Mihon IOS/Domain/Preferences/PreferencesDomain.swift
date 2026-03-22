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

enum ReaderSpreadBehavior: String, Codable, CaseIterable, Identifiable {
    case fullPage
    case autoSplit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullPage: return "Full page"
        case .autoSplit: return "Auto split wide pages"
        }
    }
}

struct ReaderColorFilter: Codable, Hashable {
    var enabled: Bool
    var grayscale: Double
    var dimming: Double
}

struct ReaderPreferences: Codable, Hashable {
    var mode: ReaderMode
    var spreadBehavior: ReaderSpreadBehavior
    var keepAwake: Bool
    var orientation: ReaderOrientation
    var showPageNumber: Bool
    var colorFilter: ReaderColorFilter

    init(
        mode: ReaderMode,
        spreadBehavior: ReaderSpreadBehavior,
        keepAwake: Bool,
        orientation: ReaderOrientation,
        showPageNumber: Bool,
        colorFilter: ReaderColorFilter
    ) {
        self.mode = mode
        self.spreadBehavior = spreadBehavior
        self.keepAwake = keepAwake
        self.orientation = orientation
        self.showPageNumber = showPageNumber
        self.colorFilter = colorFilter
    }

    enum CodingKeys: String, CodingKey {
        case mode
        case spreadBehavior
        case keepAwake
        case orientation
        case showPageNumber
        case colorFilter
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(ReaderMode.self, forKey: .mode) ?? .pagerDefault
        spreadBehavior = try container.decodeIfPresent(ReaderSpreadBehavior.self, forKey: .spreadBehavior) ?? .fullPage
        keepAwake = try container.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? true
        orientation = try container.decodeIfPresent(ReaderOrientation.self, forKey: .orientation) ?? .system
        showPageNumber = try container.decodeIfPresent(Bool.self, forKey: .showPageNumber) ?? true
        colorFilter = try container.decodeIfPresent(ReaderColorFilter.self, forKey: .colorFilter)
            ?? ReaderColorFilter(enabled: false, grayscale: 0, dimming: 0)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(spreadBehavior, forKey: .spreadBehavior)
        try container.encode(keepAwake, forKey: .keepAwake)
        try container.encode(orientation, forKey: .orientation)
        try container.encode(showPageNumber, forKey: .showPageNumber)
        try container.encode(colorFilter, forKey: .colorFilter)
    }
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

    static var recommendedMemoryCacheLimitMB: Int {
        switch deviceMemoryClass {
        case .low:
            return 64
        case .medium:
            return 96
        case .high:
            return 144
        }
    }

    static var recommendedImageCacheCountLimit: Int {
        switch deviceMemoryClass {
        case .low:
            return 80
        case .medium:
            return 120
        case .high:
            return 160
        }
    }

    init(
        imagePrefetchCount: Int = 2,
        historyLimit: Int = 100,
        showDiagnostics: Bool = false,
        aggressiveImageRetry: Bool = false,
        memoryCacheLimitMB: Int = AdvancedPreferences.recommendedMemoryCacheLimitMB,
        imageCacheCountLimit: Int = AdvancedPreferences.recommendedImageCacheCountLimit
    ) {
        self.imagePrefetchCount = imagePrefetchCount
        self.historyLimit = historyLimit
        self.showDiagnostics = showDiagnostics
        self.aggressiveImageRetry = aggressiveImageRetry
        self.memoryCacheLimitMB = memoryCacheLimitMB
        self.imageCacheCountLimit = imageCacheCountLimit
    }

    private enum DeviceMemoryClass {
        case low
        case medium
        case high
    }

    private static var deviceMemoryClass: DeviceMemoryClass {
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let totalGB = Double(totalBytes) / Double(1_073_741_824)
        if totalGB < 4 {
            return .low
        }
        if totalGB < 7 {
            return .medium
        }
        return .high
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

