//
//  TrackingViews.swift
//  Mihon IOS
//

import SwiftUI

struct TrackingCenterView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            ForEach(TrackerService.allCases) { service in
                LabeledContent(service.rawValue, value: model.bindings().contains(where: { $0.service == service }) ? "In use" : "Available")
            }
        }
        .navigationTitle("Tracking")
    }
}

struct MangaTrackingView: View {
    @EnvironmentObject private var model: AppModel
    let manga: Manga

    var body: some View {
        List {
            Section("Linked") {
                if model.trackerBindings(for: manga).isEmpty {
                    Text("No trackers linked.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.trackerBindings(for: manga)) { binding in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(binding.service.rawValue)
                                .font(.headline)
                            Text("\(binding.status) • \(binding.progressText)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                model.unlinkTracker(binding)
                            } label: {
                                Label("Unlink", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section("Add Tracker") {
                ForEach(TrackerService.allCases) { service in
                    Button {
                        model.linkTracker(service: service, to: manga)
                    } label: {
                        Label(service.rawValue, systemImage: service.systemImage)
                    }
                }
            }

            Section("Search") {
                NavigationLink {
                    TrackerSearchView(manga: manga)
                } label: {
                    Label("Search trackers", systemImage: "magnifyingglass")
                }
            }
        }
        .navigationTitle("Tracking")
    }
}

struct TrackerSearchView: View {
    let manga: Manga
    @State private var query = ""

    var body: some View {
        List {
            ForEach(TrackerService.allCases) { service in
                VStack(alignment: .leading, spacing: 4) {
                    Text(service.rawValue)
                        .font(.headline)
                    Text(query.isEmpty ? manga.title : query)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .searchable(text: $query, prompt: "Search tracker title")
        .navigationTitle("Tracker Search")
    }
}
