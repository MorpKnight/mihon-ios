//
//  AppStateStore.swift
//  Mihon IOS
//

import Foundation

struct AppStateStore {
    private let defaults: UserDefaults
    private let key = "mihon_ios.persisted_state"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func load() -> PersistedState {
        guard
            let data = defaults.data(forKey: key),
            let state = try? decoder.decode(PersistedState.self, from: data)
        else {
            return .default
        }

        guard state.schemaVersion == PersistedState.currentSchemaVersion else {
            return migrate(state)
        }

        return state
    }

    func save(_ state: PersistedState) {
        guard let data = try? encoder.encode(state) else { return }
        defaults.set(data, forKey: key)
    }

    private func migrate(_ state: PersistedState) -> PersistedState {
        var migrated = state
        migrated.schemaVersion = PersistedState.currentSchemaVersion
        if migrated.categories.isEmpty {
            migrated.categories = PersistedState.default.categories
        }
        return migrated
    }
}
