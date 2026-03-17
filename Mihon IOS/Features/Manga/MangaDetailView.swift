//
//  MangaDetailView.swift
//  Mihon IOS
//

import SwiftUI

struct MangaDetailView: View {
    @EnvironmentObject private var model: AppModel

    let manga: Manga

    @State private var noteDraft = ""
    @State private var sortDescending = true
    @State private var showCover = false
    @State private var displayManga: Manga
    @State private var loadedChapters: [Chapter]
    @State private var isLoading = false

    init(manga: Manga) {
        self.manga = manga
        _displayManga = State(initialValue: manga)
        _loadedChapters = State(initialValue: [])
    }

    private var sortedChapters: [Chapter] {
        let items = loadedChapters.isEmpty ? model.chapters(for: displayManga) : loadedChapters
        return sortDescending ? items : items.reversed()
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        MangaCoverView(manga: displayManga, cornerRadius: 24)
                            .frame(width: 132, height: 188)
                            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .onTapGesture {
                                showCover = true
                            }

                        VStack(alignment: .leading, spacing: 10) {
                            Text(displayManga.title)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.primary)

                            Text(displayManga.author)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)

                            Label(displayManga.statusText, systemImage: "dot.radiowaves.left.and.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)

                            if !displayManga.genres.isEmpty {
                                Text(displayManga.genres.joined(separator: " • "))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                        Spacer(minLength: 0)
                    }

                    Text(displayManga.summary)
                        .font(.body)
                }
                .padding(.vertical, 8)
            }

            Section("Actions") {
                Button {
                    model.toggleLibrary(displayManga)
                } label: {
                    Label(model.isInLibrary(displayManga) ? "Remove from Library" : "Add to Library", systemImage: model.isInLibrary(displayManga) ? "minus.circle" : "plus.circle")
                }

                if model.isInLibrary(displayManga) {
                    Menu {
                        ForEach(model.categories) { category in
                            Button(category.name, systemImage: category.systemImage) {
                                model.assignCategory(category.id, to: displayManga)
                            }
                        }
                    } label: {
                        Label("Category: \(model.libraryCategory(for: displayManga)?.name ?? "Library")", systemImage: "folder")
                    }
                }

                if let startChapter = (sortedChapters.first ?? model.startChapter(for: displayManga)) {
                    NavigationLink {
                        ReaderView(manga: displayManga, initialChapter: startChapter)
                    } label: {
                        Label("Resume Reading", systemImage: "play.circle.fill")
                    }
                }

                NavigationLink {
                    MangaTrackingView(manga: displayManga)
                } label: {
                    Label("Tracking", systemImage: "person.badge.clock")
                }

                NavigationLink {
                    MangaNotesView(manga: displayManga)
                } label: {
                    Label("Notes", systemImage: "note.text")
                }

                if let migrationSource = model.migrationSource(for: displayManga) {
                    NavigationLink {
                        MigrationConfirmationView(source: migrationSource, target: displayManga)
                    } label: {
                        Label("Migrate Title", systemImage: "arrow.triangle.swap")
                    }
                } else {
                    Label("Migration unavailable", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }

                if let source = model.resolvedSourceOrNil(for: displayManga.sourceID),
                   let webURL = model.sourceWebURL(for: source, manga: displayManga) {
                    Link(destination: webURL) {
                        Label("Open in Web", systemImage: "safari")
                    }
                }

                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Refreshing source content…")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let error = model.sourceError(for: displayManga.sourceID) {
                Section {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if model.resolvedSourceOrNil(for: displayManga.sourceID) == nil {
                Section {
                    Text("This title's source is currently unavailable. Reading and local metadata remain accessible where cached.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Tracking Summary") {
                if model.trackerBindings(for: displayManga).isEmpty {
                    Text("No trackers linked.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.trackerBindings(for: displayManga)) { binding in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(binding.service.rawValue)
                                .font(.headline)
                            Text("\(binding.status) • \(binding.progressText) • Score \(binding.score)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Toggle("Newest first", isOn: $sortDescending)
            }

            Section("Chapters") {
                ForEach(sortedChapters) { chapter in
                    NavigationLink {
                        ReaderView(manga: displayManga, initialChapter: chapter)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(chapter.title)
                                Spacer()
                                if chapter.isDownloaded {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .foregroundStyle(.teal)
                                }
                            }
                            Text(chapter.releaseDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle(displayManga.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showCover) {
            CoverSheet(manga: displayManga)
        }
        .task {
            noteDraft = model.note(for: displayManga)
            guard model.supportsLiveSource(sourceID: displayManga.sourceID) else {
                loadedChapters = model.chapters(for: displayManga)
                return
            }
            isLoading = true
            displayManga = await model.refreshMangaDetails(for: displayManga)
            loadedChapters = await model.refreshChapters(for: displayManga)
            isLoading = false
        }
    }
}

private struct CoverSheet: View {
    let manga: Manga

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                MangaCoverView(manga: manga, cornerRadius: 32)
                    .frame(height: 360)

                ShareLink(item: manga.title) {
                    Label("Share Cover Metadata", systemImage: "square.and.arrow.up")
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("Cover")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct MangaNotesView: View {
    @EnvironmentObject private var model: AppModel
    let manga: Manga
    @State private var note = ""

    var body: some View {
        Form {
            TextEditor(text: $note)
                .frame(minHeight: 220)

            Button("Save Note") {
                model.saveNote(note, for: manga)
            }
        }
        .navigationTitle("Notes")
        .onAppear {
            note = model.note(for: manga)
        }
    }
}
