//
//  LibraryView.swift
//  Mihon IOS
//

import SwiftUI

struct LibraryView: View {
    private struct QuickReadTarget: Hashable, Identifiable {
        var id: String { "\(manga.id)::\(chapter.id)" }
        let manga: Manga
        let chapter: Chapter
    }

    @EnvironmentObject private var model: AppModel
    @State private var selectedCategoryID: String?
    @State private var searchText = ""
    @State private var sortMode: LibrarySortMode = .recent
    // Fix #4: Changed from a NavigationDestination push to a fullScreenCover
    // trigger, avoiding the jarring context-menu-to-push-stack animation.
    @State private var quickReadTarget: QuickReadTarget?

    private var items: [LibraryManga] {
        model.libraryItems(selectedCategoryID: selectedCategoryID, searchText: searchText, sortMode: sortMode)
    }

    var body: some View {
        let hideSensitiveCovers = model.state.securityPreferences.hideSensitiveCovers
        let continueReadingItems = model.state.libraryPreferences.showContinueReading ? model.continueReadingItems : []

        List {
            if !continueReadingItems.isEmpty {
                Section("Continue Reading") {
                    ForEach(continueReadingItems.prefix(1)) { item in
                        if let chapter = model.startChapter(for: item.manga) {
                            NavigationLink {
                                ReaderView(manga: item.manga, initialChapter: chapter)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.manga.title)
                                        .font(.headline)
                                    Text(item.progress.map { "\($0.chapterTitle ?? chapter.title) • Page \($0.pageIndex + 1) of \(max($0.totalPages, 1))" } ?? chapter.title)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                }
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
                                MangaCoverView(
                                    manga: item.manga,
                                    hideSensitiveCover: hideSensitiveCovers,
                                    allowsAdultContent: model.source(for: item.manga.sourceID)?.allowsAdultContent ?? false
                                )
                                    .frame(width: 54, height: 74)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.manga.title)
                                        .font(.headline)
                                    Text(model.categoryName(for: item.entry.categoryID))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: 8) {
                                        if let progress = item.progress {
                                            Text("\(progress.chapterTitle ?? "Chapter") • Page \(progress.pageIndex + 1) of \(max(progress.totalPages, 1))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        if model.state.libraryPreferences.showDownloadedBadge,
                                           model.isTitleDownloaded(manga: item.manga) {
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
                            // Fix #4: Trigger a fullScreenCover (below) instead of
                            // a NavigationDestination push. Context menus should
                            // drive state/modals rather than directly navigating.
                            Button {
                                if let chapter = model.startChapter(for: item.manga) {
                                    quickReadTarget = QuickReadTarget(manga: item.manga, chapter: chapter)
                                }
                            } label: {
                                Label("Read", systemImage: "book")
                            }

                            if !model.state.securityPreferences.lockLibraryEdits {
                                Button(role: .destructive) {
                                    model.toggleLibrary(item.manga)
                                } label: {
                                    Label("Remove from Library", systemImage: "trash")
                                }
                            }
                        }
                        .swipeActions {
                            if !model.state.securityPreferences.lockLibraryEdits {
                                Button(role: .destructive) {
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
        // Fix #3: Category filter moved out of the List and into a pinned
        // horizontal pill row below the navigation bar, following modern iOS
        // content-filter patterns (HIG: https://developer.apple.com/design/human-interface-guidelines).
        .safeAreaInset(edge: .top, spacing: 0) {
            if !model.categories.isEmpty {
                CategoryPillFilterView(
                    categories: model.categories,
                    selectedCategoryID: $selectedCategoryID
                )
            }
        }
        // Fix #4: Use fullScreenCover instead of navigationDestination to
        // present the reader after a context-menu action, avoiding the
        // jarring push animation glitch.
        .fullScreenCover(item: $quickReadTarget) { target in
            NavigationStack {
                ReaderView(manga: target.manga, initialChapter: target.chapter)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close", systemImage: "xmark") {
                                quickReadTarget = nil
                            }
                        }
                    }
            }
        }
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

// MARK: - Category Pill Filter

/// Fix #3: A horizontally scrollable row of pill-style filter buttons pinned
/// just below the navigation bar. This pattern is recommended by Apple HIG for
/// top-level content filtering — it's roomier than a segmented Picker inside a
/// List and scales gracefully as the number of categories grows.
private struct CategoryPillFilterView: View {
    let categories: [Category]
    @Binding var selectedCategoryID: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pillButton(label: "All", id: nil)
                ForEach(categories) { category in
                    pillButton(label: category.name, id: category.id)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private func pillButton(label: String, id: String?) -> some View {
        let isSelected = selectedCategoryID == id
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedCategoryID = id
            }
        } label: {
            Text(label)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    isSelected
                        ? AnyShapeStyle(Color.accentColor)
                        : AnyShapeStyle(Color.secondary.opacity(0.15))
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }
}
