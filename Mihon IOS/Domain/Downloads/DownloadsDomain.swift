//
//  DownloadsDomain.swift
//  Mihon IOS
//

import Foundation

enum DownloadState: String, Hashable {
    case queued
    case downloading
    case paused
    case complete
    case failed
}

struct DownloadJob: Identifiable, Hashable {
    let id: UUID
    let mangaID: String
    let chapterID: String
    let sourceID: String
    let queuedAt: Date
    let manga: Manga
    let chapter: Chapter
    var progress: Double
    var state: DownloadState
    var errorMessage: String?
}
