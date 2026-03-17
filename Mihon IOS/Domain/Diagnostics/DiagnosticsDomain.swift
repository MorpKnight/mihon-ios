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

struct DiagnosticLogEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    let kind: DiagnosticLogKind
    let title: String
    let message: String
    let metadata: [String: String]
}

