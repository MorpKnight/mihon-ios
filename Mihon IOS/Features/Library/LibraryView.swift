//
//  LibraryView.swift
//  Mihon IOS
//

import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedCategoryID: String?
    @State private var searchText = ""
    @State private var sortMode: LibrarySortMode = .recent

    private var items: [LibraryManga] {
        model.libraryItems(selectedCategoryID: selectedCategoryID, searchText: searchText, sortMode: sortMode)
    }

    var body: some View {
        List {
            if model.state.libraryPreferences.showContinueReading && !model.continueReadingItems.isEmpty {
                Section("Continue Reading") {
                    ForEach(model.continueReadingItems.prefix(3)) { item in
                        if let chapter = model.startChapter(for: item.manga) {
                            NavigationLink {
                                ReaderView(manga: item.manga, initialChapter: chapter)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.manga.title)
                                        .font(.headline)
                                    Text(item.progress.map { "Page \($0.pageIndex + 1) • \(chapter.title)" } ?? chapter.title)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                }
            }

            Section {
                Picker("Category", selection: Binding(
                    get: { selectedCategoryID ?? "all" },
                    set: { selectedCategoryID = $0 == "all" ? nil : $0 }
                )) {
                    Text("All").tag("all")
                    ForEach(model.categories) { category in
                        Text(category.name).tag(category.id)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)
            }

            Section("Library") {
                if items.isEmpty {
                    ContentUnavailableView {
                        Label("Library is Empty", systemImage: "books.vertical")
                    } description: {
                        Text("Add titles from Browse to start your iOS library baseline.")
                    }
                    .padding(.vertical, 12)
                } else {
                    ForEach(items) { item in
                        NavigationLink {
                            MangaDetailView(manga: item.manga)
                        } label: {
                            HStack(spacing: 14) {
                                MangaCoverView(manga: item.manga)
                                    .frame(width: 54, height: 74)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.manga.title)
                                        .font(.headline)
                                    Text(model.categoryName(for: item.entry.categoryID))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: 8) {
                                        if let progress = item.progress {
                                            Text("Page \(progress.pageIndex + 1) of \(progress.totalPages)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        if model.state.libraryPreferences.showDownloadedBadge,
                                           item.latestChapter?.isDownloaded == true {
                                            Label("Downloaded", systemImage: "arrow.down.circle.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.teal)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 3)
                        }
                        .contextMenu {
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                // Example: Quick Read
                                if let chapter = model.startChapter(for: item.manga) {
                                    // Normally we would invoke a navigation hack or state via environment, but for now we just play haptic
                                }
                            } label: {
                                Label("Read", systemImage: "book")
                            }

                            if !model.state.securityPreferences.lockLibraryEdits {
                                Button(role: .destructive) {
                                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                                    model.toggleLibrary(item.manga)
                                } label: {
                                    Label("Remove from Library", systemImage: "trash")
                                }
                            }
                        }
                        .swipeActions {
                            if !model.state.securityPreferences.lockLibraryEdits {
                                Button(role: .destructive) {
                                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                                    model.toggleLibrary(item.manga)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search library")
        .navigationTitle("Library")
        .onAppear {
            sortMode = model.preferredLibrarySortMode()
        }
        .onChange(of: sortMode) { _, newValue in
            model.setLibrarySortMode(newValue)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sortMode) {
                        ForEach(LibrarySortMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                }

                NavigationLink {
                    LibrarySettingsView()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }

                NavigationLink {
                    CategoryManagementView()
                } label: {
                    Image(systemName: "folder.badge.plus")
                }

                NavigationLink {
                    LibraryBatchMigrationView()
                } label: {
                    Image(systemName: "arrow.triangle.swap")
                }
            }
        }
    }
}
