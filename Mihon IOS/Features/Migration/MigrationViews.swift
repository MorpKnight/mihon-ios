//
//  MigrationViews.swift
//  Mihon IOS
//

import SwiftUI

struct MigrationSourcesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            ForEach(model.visibleSources.filter { $0.kind == .remote }) { source in
                NavigationLink {
                    MigrationSearchView(source: source)
                } label: {
                    SourceRow(source: source)
                }
            }
        }
        .navigationTitle("Migrate Source")
    }
}

struct MigrationSearchView: View {
    @EnvironmentObject private var model: AppModel

    let source: Source
    @State private var query = ""

    private var mangas: [Manga] {
        model.mangas(for: source).filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        let hideSensitiveCovers = model.state.securityPreferences.hideSensitiveCovers

        List {
            ForEach(mangas) { manga in
                NavigationLink {
                    MigrationConfirmationView(source: source, target: manga)
                } label: {
                    MangaRow(
                        manga: manga,
                        hideSensitiveCover: hideSensitiveCovers,
                        allowsAdultContent: model.source(for: manga.sourceID)?.allowsAdultContent ?? false
                    )
                }
            }
        }
        .searchable(text: $query, prompt: "Find target title")
        .navigationTitle("Search \(source.name)")
    }
}

struct MigrationConfirmationView: View {
    @EnvironmentObject private var model: AppModel
    let source: Source
    let target: Manga

    var body: some View {
        let hideSensitiveCovers = model.state.securityPreferences.hideSensitiveCovers

        List {
            Section("Target") {
                MangaRow(
                    manga: target,
                    hideSensitiveCover: hideSensitiveCovers,
                    allowsAdultContent: model.source(for: target.sourceID)?.allowsAdultContent ?? false
                )
            }

            Section("Candidates") {
                ForEach(model.migrationCandidates(for: target)) { candidate in
                    NavigationLink {
                        MigrationConfigView(source: candidate.source, target: candidate.manga)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(candidate.manga.title)
                                .font(.headline)
                            Text(candidate.source.name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Confirm Migration")
    }
}

struct MigrationConfigView: View {
    let source: Source
    let target: Manga

    @State private var transferReading = true
    @State private var transferCategories = true
    @State private var transferTracking = true
    @State private var transferHistory = true

    var body: some View {
        Form {
            Section("Target") {
                LabeledContent("Source", value: source.name)
                LabeledContent("Manga", value: target.title)
            }

            Section("Transfer") {
                Toggle("Reading progress", isOn: $transferReading)
                Toggle("Categories", isOn: $transferCategories)
                Toggle("Tracking", isOn: $transferTracking)
                Toggle("History", isOn: $transferHistory)
            }
        }
        .navigationTitle("Migration Config")
    }
}
