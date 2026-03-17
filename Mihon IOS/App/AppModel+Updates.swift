//
//  AppModel+Updates.swift
//  Mihon IOS
//

import Foundation

extension AppModel {
    var unreadUpdatesCount: Int {
        updateFeed.reduce(0) { partial, item in
            let lastSeen = state.updatesLastSeenChapterIDByMangaID[item.manga.id]
            let isUnread = lastSeen != item.chapter.id
            return partial + (isUnread ? 1 : 0)
        }
    }

    func markUpdatesSeen(_ items: [UpdateFeedItem]) {
        guard !items.isEmpty else { return }
        var changed = false
        for item in items {
            if state.updatesLastSeenChapterIDByMangaID[item.manga.id] != item.chapter.id {
                state.updatesLastSeenChapterIDByMangaID[item.manga.id] = item.chapter.id
                changed = true
            }
        }
        if changed {
            persist()
        }
    }

    func markAllUpdatesSeen() {
        let items = updateFeed
        guard !items.isEmpty else { return }
        var changed = false
        for item in items {
            if state.updatesLastSeenChapterIDByMangaID[item.manga.id] != item.chapter.id {
                state.updatesLastSeenChapterIDByMangaID[item.manga.id] = item.chapter.id
                changed = true
            }
        }
        if changed {
            persist()
        }
    }
}

