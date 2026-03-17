//
//  ImportDomain.swift
//  Mihon IOS
//

import Foundation

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

