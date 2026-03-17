//
//  MangaDomain.swift
//  Mihon IOS
//

import Foundation

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

