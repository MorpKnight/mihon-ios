//
//  UpdatesView.swift
//  Mihon IOS
//

import SwiftUI

struct UpdatesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""
    @State private var downloadedOnly = false

    var body: some View {
        List {
            Section {
                Toggle("Downloaded only", isOn: $downloadedOnly)
            }

            let items = model.updateFeed(searchText: searchText, downloadedOnly: downloadedOnly)
            if items.isEmpty {
                ContentUnavailableView(
                    "No library updates",
                    systemImage: "sparkles.rectangle.stack",
                    description: Text("Library items with new chapters will surface here.")
                )
                .padding(.vertical, 12)
            } else {
                ForEach(items) { item in
                    NavigationLink {
                        MangaDetailView(manga: item.manga)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.manga.title)
                                    .font(.headline)
                                Spacer()
                                Text(item.chapter.releaseDate, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(item.chapter.title)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if item.chapter.isDownloaded {
                                Label("Downloaded", systemImage: "arrow.down.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.teal)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search updates")
        .navigationTitle("Updates")
    }
}
