//
//  FileDatabaseCoordinator.swift
//  Mihon IOS
//

import Foundation

struct DatabaseSnapshot: Codable, Hashable {
    static let diagnosticsMaxEntries = 1_000
    static let diagnosticsRetentionDays = 30

    var state: PersistedState
    var imports: [ImportRecord]
    var importJobs: [ImportJob]
    var repoRecords: [SourceRepoRecord]
    var diagnostics: [DiagnosticLogEntry]
    var sourceErrors: [String: String]
    var pageLoadErrors: [String: String]
    var downloadedChapters: [String: [Chapter]]

    static let empty = DatabaseSnapshot(state: .default, imports: [], importJobs: [], repoRecords: [], diagnostics: [], sourceErrors: [:], pageLoadErrors: [:])

    enum CodingKeys: String, CodingKey {
        case state
        case imports
        case importJobs
        case repoRecords
        case diagnostics
        case sourceErrors
        case pageLoadErrors
        case downloadedChapters
        case cachedManga
        case cachedChapters
    }

    init(state: PersistedState, imports: [ImportRecord], importJobs: [ImportJob], repoRecords: [SourceRepoRecord]) {
        self.state = state
        self.imports = imports
        self.importJobs = importJobs
        self.repoRecords = repoRecords
        self.diagnostics = []
        self.sourceErrors = [:]
        self.pageLoadErrors = [:]
        self.downloadedChapters = [:]
    }

    init(
        state: PersistedState,
        imports: [ImportRecord],
        importJobs: [ImportJob],
        repoRecords: [SourceRepoRecord],
        diagnostics: [DiagnosticLogEntry],
        sourceErrors: [String: String] = [:],
        pageLoadErrors: [String: String] = [:],
        downloadedChapters: [String: [Chapter]] = [:]
    ) {
        self.state = state
        self.imports = imports
        self.importJobs = importJobs
        self.repoRecords = repoRecords
        self.diagnostics = diagnostics
        self.sourceErrors = sourceErrors
        self.pageLoadErrors = pageLoadErrors
        self.downloadedChapters = downloadedChapters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decodeIfPresent(PersistedState.self, forKey: .state) ?? .default
        imports = try container.decodeIfPresent([ImportRecord].self, forKey: .imports) ?? []
        importJobs = try container.decodeIfPresent([ImportJob].self, forKey: .importJobs) ?? []
        repoRecords = try container.decodeIfPresent([SourceRepoRecord].self, forKey: .repoRecords) ?? []
        diagnostics = try container.decodeIfPresent([DiagnosticLogEntry].self, forKey: .diagnostics) ?? []
        sourceErrors = try container.decodeIfPresent([String: String].self, forKey: .sourceErrors) ?? [:]
        pageLoadErrors = try container.decodeIfPresent([String: String].self, forKey: .pageLoadErrors) ?? [:]
        let downloaded = try container.decodeIfPresent([String: [Chapter]].self, forKey: .downloadedChapters)
        if let downloaded {
            downloadedChapters = downloaded
        } else {
            let legacyChapters = try container.decodeIfPresent([String: [Chapter]].self, forKey: .cachedChapters) ?? [:]
            downloadedChapters = legacyChapters.reduce(into: [:]) { partialResult, pair in
                let offline = pair.value.filter { $0.isDownloaded || !$0.pages.isEmpty }
                if !offline.isEmpty {
                    partialResult[pair.key] = offline
                }
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        try container.encode(imports, forKey: .imports)
        try container.encode(importJobs, forKey: .importJobs)
        try container.encode(repoRecords, forKey: .repoRecords)
        try container.encode(diagnostics, forKey: .diagnostics)
        try container.encode(sourceErrors, forKey: .sourceErrors)
        try container.encode(pageLoadErrors, forKey: .pageLoadErrors)
        try container.encode(downloadedChapters, forKey: .downloadedChapters)
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
            let migrated = DatabaseSnapshot(state: migratedState(), imports: [], importJobs: [], repoRecords: [], diagnostics: [], sourceErrors: [:], pageLoadErrors: [:])
            saveSnapshot(migrated)
            return migrated
        }

        guard
            let data = try? Data(contentsOf: snapshotURL),
            let snapshot = try? decoder.decode(DatabaseSnapshot.self, from: data)
        else {
            return DatabaseSnapshot(state: migratedState(), imports: [], importJobs: [], repoRecords: [], diagnostics: [], sourceErrors: [:], pageLoadErrors: [:])
        }

        var normalized = snapshot
        normalized.state.schemaVersion = PersistedState.currentSchemaVersion
        normalized.state.sourceRepos = normalized.repoRecords.map(\.url)
        normalized.diagnostics = normalizeDiagnostics(normalized.diagnostics)
        return normalized
    }

    func saveSnapshot(_ snapshot: DatabaseSnapshot) {
        ensureDirectories()
        var normalized = snapshot
        normalized.diagnostics = normalizeDiagnostics(normalized.diagnostics)
        guard let data = try? encoder.encode(normalized) else { return }
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

    private func normalizeDiagnostics(_ logs: [DiagnosticLogEntry]) -> [DiagnosticLogEntry] {
        let retentionCutoff = Calendar.current.date(byAdding: .day, value: -DatabaseSnapshot.diagnosticsRetentionDays, to: .now) ?? .distantPast
        let filtered = logs
            .filter { $0.timestamp >= retentionCutoff }
            .sorted { $0.timestamp > $1.timestamp }
        return Array(filtered.prefix(DatabaseSnapshot.diagnosticsMaxEntries))
    }
}
