//
//  FileDatabaseCoordinator.swift
//  Mihon IOS
//

import Foundation

struct DatabaseSnapshot: Codable, Hashable {
    var state: PersistedState
    var imports: [ImportRecord]
    var importJobs: [ImportJob]

    static let empty = DatabaseSnapshot(state: .default, imports: [], importJobs: [])
}

final class FileDatabaseCoordinator: DatabaseCoordinator {
    let databaseDirectoryURL: URL

    private let stateStore: AppStateStore
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let snapshotURL: URL

    init(
        stateStore: AppStateStore = AppStateStore(),
        fileManager: FileManager = .default
    ) {
        self.stateStore = stateStore
        self.fileManager = fileManager

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.databaseDirectoryURL = appSupport.appendingPathComponent("MihonDatabase", isDirectory: true)
        self.snapshotURL = databaseDirectoryURL.appendingPathComponent("snapshot.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        ensureDirectories()
    }

    func loadSnapshot() -> DatabaseSnapshot {
        guard fileManager.fileExists(atPath: snapshotURL.path) else {
            let migrated = DatabaseSnapshot(state: migratedState(), imports: [], importJobs: [])
            saveSnapshot(migrated)
            return migrated
        }

        guard
            let data = try? Data(contentsOf: snapshotURL),
            let snapshot = try? decoder.decode(DatabaseSnapshot.self, from: data)
        else {
            return DatabaseSnapshot(state: migratedState(), imports: [], importJobs: [])
        }

        var normalized = snapshot
        normalized.state.schemaVersion = PersistedState.currentSchemaVersion
        return normalized
    }

    func saveSnapshot(_ snapshot: DatabaseSnapshot) {
        ensureDirectories()
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: snapshotURL, options: .atomic)
    }

    private func migratedState() -> PersistedState {
        var state = stateStore.load()
        state.schemaVersion = PersistedState.currentSchemaVersion
        return state
    }

    private func ensureDirectories() {
        try? fileManager.createDirectory(at: databaseDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        try? fileManager.createDirectory(at: importsDirectoryURL, withIntermediateDirectories: true, attributes: nil)
    }

    var importsDirectoryURL: URL {
        databaseDirectoryURL.appendingPathComponent("Imports", isDirectory: true)
    }
}
