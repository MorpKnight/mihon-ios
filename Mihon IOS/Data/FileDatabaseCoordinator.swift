//
//  FileDatabaseCoordinator.swift
//  Mihon IOS
//

import Foundation

struct DatabaseSnapshot: Codable, Hashable {
    var state: PersistedState
    var imports: [ImportRecord]
    var importJobs: [ImportJob]
    var repoRecords: [SourceRepoRecord]
    var diagnostics: [DiagnosticLogEntry]
    var cachedManga: [String: [Manga]]
    var cachedChapters: [String: [Chapter]]

    static let empty = DatabaseSnapshot(state: .default, imports: [], importJobs: [], repoRecords: [], diagnostics: [])

    enum CodingKeys: String, CodingKey {
        case state
        case imports
        case importJobs
        case repoRecords
        case diagnostics
        case cachedManga
        case cachedChapters
    }

    init(state: PersistedState, imports: [ImportRecord], importJobs: [ImportJob], repoRecords: [SourceRepoRecord]) {
        self.state = state
        self.imports = imports
        self.importJobs = importJobs
        self.repoRecords = repoRecords
        self.diagnostics = []
        self.cachedManga = [:]
        self.cachedChapters = [:]
    }

    init(state: PersistedState, imports: [ImportRecord], importJobs: [ImportJob], repoRecords: [SourceRepoRecord], diagnostics: [DiagnosticLogEntry], cachedManga: [String: [Manga]] = [:], cachedChapters: [String: [Chapter]] = [:]) {
        self.state = state
        self.imports = imports
        self.importJobs = importJobs
        self.repoRecords = repoRecords
        self.diagnostics = diagnostics
        self.cachedManga = cachedManga
        self.cachedChapters = cachedChapters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decodeIfPresent(PersistedState.self, forKey: .state) ?? .default
        imports = try container.decodeIfPresent([ImportRecord].self, forKey: .imports) ?? []
        importJobs = try container.decodeIfPresent([ImportJob].self, forKey: .importJobs) ?? []
        repoRecords = try container.decodeIfPresent([SourceRepoRecord].self, forKey: .repoRecords) ?? []
        diagnostics = try container.decodeIfPresent([DiagnosticLogEntry].self, forKey: .diagnostics) ?? []
        cachedManga = try container.decodeIfPresent([String: [Manga]].self, forKey: .cachedManga) ?? [:]
        cachedChapters = try container.decodeIfPresent([String: [Chapter]].self, forKey: .cachedChapters) ?? [:]
    }
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
            let migrated = DatabaseSnapshot(state: migratedState(), imports: [], importJobs: [], repoRecords: [], diagnostics: [])
            saveSnapshot(migrated)
            return migrated
        }

        guard
            let data = try? Data(contentsOf: snapshotURL),
            let snapshot = try? decoder.decode(DatabaseSnapshot.self, from: data)
        else {
            return DatabaseSnapshot(state: migratedState(), imports: [], importJobs: [], repoRecords: [], diagnostics: [])
        }

        var normalized = snapshot
        normalized.state.schemaVersion = PersistedState.currentSchemaVersion
        normalized.state.sourceRepos = normalized.repoRecords.map(\.url)
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
        try? fileManager.createDirectory(at: downloadsDirectoryURL, withIntermediateDirectories: true, attributes: nil)
    }

    var importsDirectoryURL: URL {
        databaseDirectoryURL.appendingPathComponent("Imports", isDirectory: true)
    }

    var downloadsDirectoryURL: URL {
        databaseDirectoryURL.appendingPathComponent("Downloads", isDirectory: true)
    }
}
