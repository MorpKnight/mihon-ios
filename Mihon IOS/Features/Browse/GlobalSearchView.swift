//
//  GlobalSearchView.swift
//  Mihon IOS
//

import SwiftUI

struct GlobalSearchView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""

    var body: some View {
        let results = model.globalSearchResults(query: query)

        List {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "Search all sources",
                    systemImage: "magnifyingglass",
                    description: Text("Enter a title, author, or genre to search across enabled sources.")
                )
                .padding(.vertical, 12)
            } else if results.isEmpty {
                ContentUnavailableView(
                    "No results",
                    systemImage: "books.vertical",
                    description: Text("Try a broader query or enable more sources.")
                )
                .padding(.vertical, 12)
            } else {
                ForEach(results, id: \.0.id) { source, results in
                    Section(source.name) {
                        ForEach(results) { manga in
                            NavigationLink {
                                MangaDetailView(manga: manga)
                            } label: {
                                MangaRow(
                                    manga: manga,
                                    hideSensitiveCover: model.state.securityPreferences.hideSensitiveCovers,
                                    allowsAdultContent: model.source(for: manga.sourceID)?.allowsAdultContent ?? false
                                )
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search all sources")
        .navigationTitle("Global Search")
    }
}
