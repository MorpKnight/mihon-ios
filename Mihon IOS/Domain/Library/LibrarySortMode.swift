//
//  LibrarySortMode.swift
//  Mihon IOS
//

import Foundation

enum LibrarySortMode: String, Codable, CaseIterable, Identifiable {
    case recent
    case alphabetical
    case chapterCount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: return "Recent"
        case .alphabetical: return "A-Z"
        case .chapterCount: return "Chapters"
        }
    }
}

