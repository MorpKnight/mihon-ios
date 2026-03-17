//
//  BackupMigrationDomain.swift
//  Mihon IOS
//

import Foundation

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

