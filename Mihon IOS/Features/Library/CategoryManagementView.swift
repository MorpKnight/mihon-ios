//
//  CategoryManagementView.swift
//  Mihon IOS
//

import SwiftUI

struct CategoryManagementView: View {
    @EnvironmentObject private var model: AppModel
    @State private var newCategoryName = ""

    var body: some View {
        List {
            Section("Create Category") {
                TextField("New category name", text: $newCategoryName)
                    .disabled(model.state.securityPreferences.lockLibraryEdits)
                Button("Add Category") {
                    model.addCategory(named: newCategoryName)
                    newCategoryName = ""
                }
                .disabled(model.state.securityPreferences.lockLibraryEdits)
            }

            Section("Current Categories") {
                if model.categories.isEmpty {
                    ContentUnavailableView(
                        "No Categories Yet",
                        systemImage: "folder.badge.plus",
                        description: Text("Create your own categories here. New installs no longer start with default category groups.")
                    )
                } else {
                    ForEach(model.categories) { category in
                        NavigationLink {
                            CategoryDetailView(category: category)
                        } label: {
                            Label(category.name, systemImage: category.systemImage)
                        }
                    }
                }
            }
        }
        .navigationTitle("Categories")
    }
}

private struct CategoryDetailView: View {
    @EnvironmentObject private var model: AppModel
    let category: Category
    @State private var name: String

    init(category: Category) {
        self.category = category
        _name = State(initialValue: category.name)
    }

    var body: some View {
        Form {
            TextField("Name", text: $name)
                .disabled(model.state.securityPreferences.lockLibraryEdits)
            Button("Save Name") {
                model.renameCategory(category.id, to: name)
            }
            .disabled(model.state.securityPreferences.lockLibraryEdits)

            Button("Delete Category", role: .destructive) {
                model.deleteCategory(category.id)
            }
            .disabled(model.state.securityPreferences.lockLibraryEdits)
        }
        .navigationTitle(category.name)
    }
}

struct LibrarySettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Display") {
                Toggle("Show Continue Reading", isOn: Binding(
                    get: { model.state.libraryPreferences.showContinueReading },
                    set: model.setContinueReadingVisible
                ))
                Toggle("Show Downloaded Badge", isOn: Binding(
                    get: { model.state.libraryPreferences.showDownloadedBadge },
                    set: model.setDownloadedBadgeVisible
                ))
                Toggle("Show Unread Badge", isOn: Binding(
                    get: { model.state.libraryPreferences.showUnreadBadge },
                    set: model.setUnreadBadgeVisible
                ))
            }

            Section("Defaults") {
                Picker("Sort", selection: Binding(
                    get: { model.state.libraryPreferences.sortMode },
                    set: model.setLibrarySortMode
                )) {
                    ForEach(LibrarySortMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                if model.categories.isEmpty {
                    LabeledContent("Default Category", value: "Uncategorized")
                    Text("Titles added to the library stay uncategorized until you create and assign your own categories.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Default Category", selection: Binding(
                        get: { model.state.libraryPreferences.defaultCategoryID },
                        set: model.setDefaultCategoryID
                    )) {
                        ForEach(model.categories) { category in
                            Text(category.name).tag(category.id)
                        }
                    }
                }
            }
        }
        .navigationTitle("Library Settings")
    }
}

struct LibraryBatchMigrationView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let hideSensitiveCovers = model.state.securityPreferences.hideSensitiveCovers

        List {
            ForEach(model.libraryItems(selectedCategoryID: nil)) { item in
                if let source = model.migrationSource(for: item.manga) {
                    NavigationLink {
                        MigrationConfirmationView(source: source, target: item.manga)
                    } label: {
                        MangaRow(
                            manga: item.manga,
                            hideSensitiveCover: hideSensitiveCovers,
                            allowsAdultContent: model.source(for: item.manga.sourceID)?.allowsAdultContent ?? false
                        )
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        MangaRow(
                            manga: item.manga,
                            hideSensitiveCover: hideSensitiveCovers,
                            allowsAdultContent: model.source(for: item.manga.sourceID)?.allowsAdultContent ?? false
                        )
                        Text("Migration unavailable because the source could not be resolved.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Batch Migration")
    }
}
