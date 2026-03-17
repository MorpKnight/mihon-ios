//
//  TrackingDomain.swift
//  Mihon IOS
//

import Foundation

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

