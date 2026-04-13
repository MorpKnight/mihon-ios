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
    @State private var showDownloadAllConfirm = false
    @State private var showRemoveAllDownloadsConfirm = false

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
        let hideSensitiveCovers = model.state.securityPreferences.hideSensitiveCovers
        let allowsAdultContent = model.source(for: displayManga.sourceID)?.allowsAdultContent ?? false

        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        MangaCoverView(
                            manga: displayManga,
                            hideSensitiveCover: hideSensitiveCovers,
                            allowsAdultContent: allowsAdultContent,
                            cornerRadius: 24
                        )
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

                if displayManga.sourceID != "local-files" {
                    let titleJobs = model.downloadJobs.filter { $0.mangaID == displayManga.id && $0.sourceID == displayManga.sourceID }
                    let chapterList = sortedChapters
                    if !chapterList.isEmpty {
                        Button {
                            if chapterList.count > 20 {
                                showDownloadAllConfirm = true
                            } else {
                                model.enqueueDownloadAllChapters(manga: displayManga, chapters: chapterList)
                            }
                        } label: {
                            Label("Download all chapters", systemImage: "arrow.down.circle")
                        }

                        Button(role: .destructive) {
                            if chapterList.count > 20 {
                                showRemoveAllDownloadsConfirm = true
                            } else {
                                model.removeAllDownloads(manga: displayManga)
                            }
                        } label: {
                            Label("Remove all downloads", systemImage: "trash")
                        }
                    }

                    if !titleJobs.isEmpty {
                        MangaDownloadAggregateView(jobs: titleJobs)
                    }
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

                if let startChapter = model.startChapter(for: displayManga) ?? sortedChapters.first {
                    NavigationLink {
                        ReaderView(manga: displayManga, initialChapter: startChapter)
                    } label: {
                        if model.progress(for: displayManga) != nil {
                            Label("Resume Reading", systemImage: "play.circle.fill")
                        } else {
                            Label("Start Reading", systemImage: "play.circle")
                        }
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
                    let progress = model.progress(for: displayManga)
                    let isCurrentProgressChapter = progress?.chapterID == chapter.id
                    NavigationLink {
                        ReaderView(manga: displayManga, initialChapter: chapter)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(chapter.title)
                                Spacer()
                                if isCurrentProgressChapter {
                                    Image(systemName: "book.fill")
                                        .foregroundStyle(.blue)
                                }
                                if chapter.isDownloaded {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .foregroundStyle(.teal)
                                }
                            }
                            Text(chapter.releaseDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if isCurrentProgressChapter, let progress {
                                Text("Last read: \(model.progressDisplayText(for: displayManga, fallbackChapter: chapter) ?? "Page \(progress.pageIndex + 1) of \(max(progress.totalPages, 1))")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            if !chapter.isDownloaded, let job = model.downloadJob(for: displayManga, chapter: chapter) {
                                ChapterDownloadInlineStatusView(job: job)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .contextMenu {
                        if displayManga.sourceID == "local-files" {
                            EmptyView()
                        } else
                        if chapter.isDownloaded {
                            Button(role: .destructive) {
                                model.removeDownloaded(manga: displayManga, chapter: chapter)
                            } label: {
                                Label("Remove download", systemImage: "trash")
                            }
                        } else if let job = model.downloadJob(for: displayManga, chapter: chapter) {
                            switch job.state {
                            case .queued, .downloading:
                                Button(role: .destructive) {
                                    model.cancelDownload(jobID: job.id)
                                } label: {
                                    Label("Cancel download", systemImage: "xmark.circle")
                                }
                            case .failed:
                                Button {
                                    model.retryDownload(jobID: job.id)
                                } label: {
                                    Label("Retry download", systemImage: "arrow.clockwise")
                                }
                                Button(role: .destructive) {
                                    model.cancelDownload(jobID: job.id)
                                } label: {
                                    Label("Cancel download", systemImage: "xmark.circle")
                                }
                            case .complete:
                                Button(role: .destructive) {
                                    model.removeDownloaded(manga: displayManga, chapter: chapter)
                                } label: {
                                    Label("Remove download", systemImage: "trash")
                                }
                            case .paused:
                                Button(role: .destructive) {
                                    model.cancelDownload(jobID: job.id)
                                } label: {
                                    Label("Cancel download", systemImage: "xmark.circle")
                                }
                            }
                        } else {
                            Button {
                                model.enqueueDownload(manga: displayManga, chapter: chapter)
                            } label: {
                                Label("Download", systemImage: "arrow.down.circle")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(displayManga.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showCover) {
            CoverSheet(
                manga: displayManga,
                hideSensitiveCover: hideSensitiveCovers,
                allowsAdultContent: allowsAdultContent
            )
        }
        .confirmationDialog("Download all chapters?", isPresented: $showDownloadAllConfirm) {
            Button("Download all", role: .none) {
                model.enqueueDownloadAllChapters(manga: displayManga, chapters: sortedChapters)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will enqueue up to \(sortedChapters.count) chapter downloads.")
        }
        .confirmationDialog("Remove all downloads?", isPresented: $showRemoveAllDownloadsConfirm) {
            Button("Remove all", role: .destructive) {
                model.removeAllDownloads(manga: displayManga)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete offline files for \(sortedChapters.count) chapters.")
        }
        .onChange(of: model.chapterCache[displayManga.id]) { _, newValue in
            if let newValue, !newValue.isEmpty {
                loadedChapters = newValue
            }
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

private struct MangaDownloadAggregateView: View {
    let jobs: [DownloadJob]

    private var total: Int { jobs.count }
    private var completed: Int { jobs.filter { $0.state == .complete }.count }
    private var failed: Int { jobs.filter { $0.state == .failed }.count }

    private var progress: Double {
        guard total > 0 else { return 0 }
        let sum = jobs.reduce(0.0) { partial, job in
            switch job.state {
            case .complete:
                return partial + 1
            case .downloading:
                return partial + min(max(job.progress, 0), 1)
            case .queued, .paused, .failed:
                return partial
            }
        }
        return min(max(sum / Double(total), 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Download Progress")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(completed)/\(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
            if failed > 0 {
                Text("\(failed) failed")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ChapterDownloadInlineStatusView: View {
    @EnvironmentObject private var model: AppModel
    let job: DownloadJob

    var body: some View {
        HStack(spacing: 10) {
            switch job.state {
            case .queued:
                ProgressView()
                    .scaleEffect(0.85)
                Text("Queued")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .downloading:
                ProgressView(value: min(max(job.progress, 0), 1))
                    .frame(maxWidth: 180)
                Text("\(Int(job.progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .paused:
                Image(systemName: "pause.circle")
                    .foregroundStyle(.secondary)
                Text("Paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Failed")
                    .font(.caption)
                    .foregroundStyle(.red)
                Button {
                    model.retryDownload(jobID: job.id)
                } label: {
                    Text("Retry")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
            case .complete:
                EmptyView()
            }
            Spacer(minLength: 0)
        }
    }
}

private struct CoverSheet: View {
    let manga: Manga
    let hideSensitiveCover: Bool
    let allowsAdultContent: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                MangaCoverView(
                    manga: manga,
                    hideSensitiveCover: hideSensitiveCover,
                    allowsAdultContent: allowsAdultContent,
                    cornerRadius: 32
                )
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
