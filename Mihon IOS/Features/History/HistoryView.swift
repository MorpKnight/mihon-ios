//
//  HistoryView.swift
//  Mihon IOS
//

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""

    var body: some View {
        List {
            Section {
                Button("Clear History", role: .destructive) {
                    model.clearHistory()
                }
            }

            if model.historyEntries(searchText: searchText).isEmpty {
                ContentUnavailableView(
                    "No history yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Open a chapter from Browse or Library to start tracking progress.")
                )
                .padding(.vertical, 12)
            } else {
                ForEach(model.historyEntries(searchText: searchText), id: \.0.id) { entry, manga, chapter in
                    NavigationLink {
                        ReaderView(manga: manga, initialChapter: chapter)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(manga.title)
                                .font(.headline)
                            Text(chapter.title)
                                .font(.subheadline)
                            Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            model.removeHistoryEntry(entry.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search history")
        .navigationTitle("History")
    }
}
