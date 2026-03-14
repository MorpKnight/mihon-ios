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
                ForEach(model.categories) { category in
                    NavigationLink {
                        CategoryDetailView(category: category)
                    } label: {
                        Label(category.name, systemImage: category.systemImage)
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
        .navigationTitle("Library Settings")
    }
}

struct LibraryBatchMigrationView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            ForEach(model.libraryItems(selectedCategoryID: nil)) { item in
                NavigationLink {
                    MigrationConfirmationView(source: model.source(for: item.manga.sourceID) ?? model.sources[0], target: item.manga)
                } label: {
                    MangaRow(manga: item.manga)
                }
            }
        }
        .navigationTitle("Batch Migration")
    }
}
