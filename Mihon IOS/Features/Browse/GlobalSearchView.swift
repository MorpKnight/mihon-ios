//
//  GlobalSearchView.swift
//  Mihon IOS
//

import SwiftUI

struct GlobalSearchView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""

    var body: some View {
        List {
            ForEach(model.globalSearchResults(query: query), id: \.0.id) { source, results in
                Section(source.name) {
                    ForEach(results) { manga in
                        NavigationLink {
                            MangaDetailView(manga: manga)
                        } label: {
                            MangaRow(manga: manga)
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search all sources")
        .navigationTitle("Global Search")
    }
}
