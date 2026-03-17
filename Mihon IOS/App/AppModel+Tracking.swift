//
//  AppModel+Tracking.swift
//  Mihon IOS
//

import Foundation

extension AppModel {
    func trackerBindings(for manga: Manga) -> [TrackerBinding] {
        state.trackers.filter { $0.mangaID == manga.id }
    }

    func linkTracker(service: TrackerService, to manga: Manga) {
        guard !state.trackers.contains(where: { $0.mangaID == manga.id && $0.service == service }) else { return }
        state.trackers.append(
            TrackerBinding(
                id: UUID(),
                mangaID: manga.id,
                service: service,
                remoteTitle: manga.title,
                status: "Reading",
                progressText: progress(for: manga).map { "\($0.pageIndex + 1) pages" } ?? "Started",
                score: "-"
            )
        )
        persist()
    }

    func unlinkTracker(_ binding: TrackerBinding) {
        state.trackers.removeAll { $0.id == binding.id }
        persist()
    }
}

