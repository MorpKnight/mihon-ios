//
//  BrowseView.swift
//  Mihon IOS
//

import SwiftUI
import UniformTypeIdentifiers

struct BrowseView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section("Browse") {
                NavigationLink {
                    SourcesView()
                } label: {
                    Label("Sources", systemImage: "globe")
                }

                NavigationLink {
                    GlobalSearchView()
                } label: {
                    Label("Global Search", systemImage: "magnifyingglass")
                }

                NavigationLink {
                    SourceCatalogView()
                } label: {
                    Label("Source Catalog", systemImage: "shippingbox")
                }

                NavigationLink {
                    MigrationSourcesView()
                } label: {
                    Label("Migration", systemImage: "arrow.triangle.swap")
                }
            }

            Section("Quick Sources") {
                ForEach(model.visibleSources.prefix(3)) { source in
                    NavigationLink {
                        SourceView(source: source)
                    } label: {
                        SourceRow(source: source)
                    }
                }
            }
        }
        .navigationTitle("Browse")
    }
}

struct SourcesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""

    private var filteredSources: [Source] {
        model.visibleSources.filter { source in
            (query.isEmpty || source.name.localizedCaseInsensitiveContains(query) || source.summary.localizedCaseInsensitiveContains(query)) &&
            model.state.browsePreferences.enabledLanguages.contains(source.language)
        }
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    SourcesFilterView()
                } label: {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
            }

            Section("Sources") {
                ForEach(filteredSources) { source in
                    NavigationLink {
                        SourceView(source: source)
                    } label: {
                        SourceRow(source: source)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Find source")
        .navigationTitle("Sources")
    }
}

struct SourceView: View {
    @EnvironmentObject private var model: AppModel

    let source: Source
    @State private var query = ""
    @State private var showingImporter = false
    @State private var feedKind: SourceFeedKind = .popular
    @State private var showingFilters = false
    @State private var isLoading = false
    @State private var runtimeManga: [Manga] = []
    @State private var sortValue = "popular"
    @State private var orderAscending = false
    @State private var selectedTypes: Set<String> = []
    @State private var includedGenres: Set<String> = []
    @State private var excludedGenres: Set<String> = []

    private var filteredManga: [Manga] {
        let items = model.mangas(for: source)
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.author.localizedCaseInsensitiveContains(query) ||
            $0.genres.joined(separator: " ").localizedCaseInsensitiveContains(query)
        }
    }

    private var displayedManga: [Manga] {
        model.supportsLiveSource(source) ? runtimeManga : filteredManga
    }

    var body: some View {
        List {
            sourceActionsSection
            mangaSection
        }
        .searchable(text: $query, prompt: "Search manga")
        .navigationTitle(source.name)
        .task {
            guard model.supportsLiveSource(source) else { return }
            await model.loadGenreTags(for: source)
            await reloadRuntimeFeed()
        }
        .onChange(of: feedKind) { _, _ in
            guard model.supportsLiveSource(source) else { return }
            Task { await reloadRuntimeFeed() }
        }
        .onSubmit(of: .search) {
            guard model.supportsLiveSource(source) else { return }
            Task { await reloadRuntimeFeed() }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.folder, .image, .zip, .mihonCBZ, .mihonEPUB],
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                model.importItems(from: urls)
            }
        }
        .sheet(isPresented: $showingFilters) {
            NavigationStack {
                RuntimeSourceFiltersView(
                    sortValue: $sortValue,
                    orderAscending: $orderAscending,
                    selectedTypes: $selectedTypes,
                    includedGenres: $includedGenres,
                    excludedGenres: $excludedGenres,
                    genres: model.genreTags(for: source.id)
                )
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var sourceActionsSection: some View {
        Section {
            NavigationLink {
                SourcePreferencesView(source: source)
            } label: {
                Label("Source Preferences", systemImage: "slider.horizontal.3")
            }

            NavigationLink {
                SourceWebView(source: source)
            } label: {
                Label("Open Source Website", systemImage: "safari")
            }

            if model.supportsLiveSource(source) {
                Button {
                    showingFilters = true
                } label: {
                    Label("Runtime Filters", systemImage: "line.3.horizontal.decrease.circle")
                }

                Picker("Feed", selection: $feedKind) {
                    ForEach(SourceFeedKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            }

            if source.kind == .local {
                Button {
                    showingImporter = true
                } label: {
                    Label("Import Local Files", systemImage: "square.and.arrow.down")
                }

                NavigationLink {
                    LocalImportsView()
                } label: {
                    Label("Local Imports", systemImage: "internaldrive")
                }
            }
        }
    }

    private var mangaSection: some View {
        Section {
            if isLoading {
                ForEach(0..<6, id: \.self) { _ in
                    loadingMangaRow
                }
            } else {
                if let error = model.sourceError(for: source.id) {
                    ContentUnavailableView("Source Error", systemImage: "wifi.exclamationmark", description: Text(error))
                }

                ForEach(displayedManga) { manga in
                    mangaRowLink(for: manga)
                }
            }
        } header: {
            Text(source.summary)
                .textCase(nil)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var loadingMangaRow: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
                .frame(width: 56, height: 74)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 140, height: 16)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 100, height: 12)
            }
        }
        .padding(.vertical, 4)
        .redacted(reason: .placeholder)
    }

    private func mangaRowLink(for manga: Manga) -> some View {
        let appModel = _model.wrappedValue
        let isInLibrary = appModel.isInLibrary(manga)

        return NavigationLink {
            MangaDetailView(manga: manga)
        } label: {
            MangaRow(manga: manga)
        }
        .contextMenu {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                appModel.toggleLibrary(manga)
            } label: {
                if isInLibrary {
                    Label("Remove from Library", systemImage: "bookmark.slash")
                } else {
                    Label("Add to Library", systemImage: "bookmark")
                }
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                appModel.toggleLibrary(manga)
            } label: {
                if isInLibrary {
                    Label("Remove", systemImage: "bookmark.slash")
                } else {
                    Label("Add", systemImage: "bookmark")
                }
            }
            .tint(isInLibrary ? .red : .blue)
        }
    }

    private func reloadRuntimeFeed() async {
        isLoading = true
        let filters: [SourceFilterValue] = [
            .sort(feedKind == .latest ? "updated" : sortValue),
            .orderAscending(orderAscending),
            .types(Array(selectedTypes).sorted()),
            .genreInclude(mode: "OR", slugs: Array(includedGenres).sorted()),
            .genreExclude(mode: "OR", slugs: Array(excludedGenres).sorted()),
        ]
        let effectiveQuery = feedKind == .search ? query : ""
        await model.refreshSourceFeed(for: source, mode: feedKind, query: effectiveQuery, filters: filters)
        runtimeManga = model.mangas(for: source)
        isLoading = false
    }
}

struct SourcesFilterView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Languages") {
                ForEach(SourceLanguage.allCases) { language in
                    Toggle(language.rawValue, isOn: Binding(
                        get: { model.state.browsePreferences.enabledLanguages.contains(language) },
                        set: { model.setBrowseLanguage(language, enabled: $0) }
                    ))
                }
            }

            Section("Visibility") {
                Toggle("Hide adult sources", isOn: Binding(
                    get: { model.state.browsePreferences.hideAdultSources },
                    set: model.setHideAdultSources
                ))
                Toggle("Enabled only", isOn: Binding(
                    get: { model.state.browsePreferences.enabledSourcesOnly },
                    set: model.setEnabledSourcesOnly
                ))
                Toggle("Pinned only", isOn: Binding(
                    get: { model.state.browsePreferences.pinnedSourcesOnly },
                    set: model.setPinnedSourcesOnly
                ))
            }
        }
        .navigationTitle("Source Filters")
    }
}

struct SourceRow: View {
    let source: Source

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: source.systemImage)
                .font(.title3)
                .foregroundStyle(source.kind == .local ? .teal : .blue)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(source.name)
                    .font(.headline)
                Text(source.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("\(source.language.rawValue) • \(source.kind == .local ? "Local" : "Remote")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if source.isPinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct RuntimeSourceFiltersView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var sortValue: String
    @Binding var orderAscending: Bool
    @Binding var selectedTypes: Set<String>
    @Binding var includedGenres: Set<String>
    @Binding var excludedGenres: Set<String>
    let genres: [GenreTag]

    private let typeOptions = ["manga", "manhwa", "manhua"]
    private let sortOptions: [(String, String)] = [
        ("Popular", "popular"),
        ("Rating", "rating"),
        ("Updated", "updated"),
        ("Bookmarked", "bookmarked"),
        ("Title", "title"),
    ]

    var body: some View {
        Form {
            Section("Sort") {
                Picker("Sort by", selection: $sortValue) {
                    ForEach(sortOptions, id: \.1) { option in
                        Text(option.0).tag(option.1)
                    }
                }

                Toggle("Ascending", isOn: $orderAscending)
            }

            Section("Type") {
                ForEach(typeOptions, id: \.self) { option in
                    Toggle(option.capitalized, isOn: binding(for: option, in: $selectedTypes))
                }
            }

            if !genres.isEmpty {
                Section("Include Genres") {
                    ForEach(genres.prefix(12)) { genre in
                        Toggle(genre.name, isOn: binding(for: genre.slug, in: $includedGenres))
                    }
                }

                Section("Exclude Genres") {
                    ForEach(genres.prefix(12)) { genre in
                        Toggle(genre.name, isOn: binding(for: genre.slug, in: $excludedGenres))
                    }
                }
            }
        }
        .navigationTitle("Runtime Filters")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private func binding(for value: String, in set: Binding<Set<String>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(value) },
            set: { enabled in
                if enabled {
                    set.wrappedValue.insert(value)
                } else {
                    set.wrappedValue.remove(value)
                }
            }
        )
    }
}

struct MangaRow: View {
    let manga: Manga

    var body: some View {
        HStack(spacing: 14) {
            MangaCoverView(manga: manga, cornerRadius: 16, overlaySystemImage: "book.closed.fill")
                .frame(width: 56, height: 74)

            VStack(alignment: .leading, spacing: 5) {
                Text(manga.title)
                    .font(.headline)
                Text(manga.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(manga.statusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct LocalImportsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingImporter = false

    var body: some View {
        List {
            Section {
                Text(model.localImportSummary())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    showingImporter = true
                } label: {
                    Label("Import from Files", systemImage: "square.and.arrow.down")
                }
            }

            if !model.importedJobs().isEmpty {
                Section("Import Jobs") {
                    ForEach(model.importedJobs()) { job in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(job.fileName)
                                .font(.headline)
                            Text("\(job.kind.rawValue.uppercased()) • \(job.status.rawValue)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(job.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Imported Titles") {
                ForEach(model.mangas(for: model.source(for: "local-files") ?? model.sources.first(where: { $0.kind == .local })!)) { manga in
                    NavigationLink {
                        MangaDetailView(manga: manga)
                    } label: {
                        MangaRow(manga: manga)
                    }
                }
            }
        }
        .navigationTitle("Local Imports")
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.folder, .image, .zip, .mihonCBZ, .mihonEPUB],
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                model.importItems(from: urls)
            }
        }
    }
}
