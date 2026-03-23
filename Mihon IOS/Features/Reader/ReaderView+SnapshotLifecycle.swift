//
//  ReaderView+SnapshotLifecycle.swift
//  Mihon IOS
//

import SwiftUI

extension ReaderView {
    func buildReaderSnapshot(
        mode: ReaderMode? = nil,
        pages: [ReaderPage]? = nil,
        imageSizes: [String: CGSize]? = nil
    ) -> ReaderContentSnapshot {
        let resolvedMode = mode ?? model.state.readerPreferences.mode
        let resolvedPages = pages ?? liveResolvedPages
        let resolvedImageSizes = imageSizes ?? pageImageSizes
        return ReaderContentSnapshot(
            chapterID: currentChapter.id,
            mode: resolvedMode,
            pages: resolvedPages,
            imageSizes: resolvedImageSizes,
            renderData: ReaderRenderData.build(
                pages: resolvedPages,
                mode: resolvedMode,
                spreadBehavior: model.state.readerPreferences.spreadBehavior,
                imageSizes: resolvedImageSizes
            )
        )
    }

    func refreshCommittedSnapshot(preferredPageIndex: Int?, animatedSync: Bool) {
        let snapshot = buildReaderSnapshot()
        if shouldDeferSnapshot(snapshot) {
            deferredSnapshot = snapshot
            deferredSnapshotPreferredPageIndex = preferredPageIndex
            return
        }
        commitSnapshot(snapshot, preferredPageIndex: preferredPageIndex, animatedSync: animatedSync)
    }

    func commitSnapshot(_ snapshot: ReaderContentSnapshot, preferredPageIndex: Int?, animatedSync: Bool) {
        let previousSnapshot = committedSnapshot
        let previousPageCount = previousSnapshot?.renderData.logicalPages.count ?? 0
        let anchor = previousSnapshot?.renderData.anchor(
            for: min(max(pageIndex, 0), max(previousPageCount - 1, 0))
        )
        committedSnapshot = snapshot
        deferredSnapshot = nil
        deferredSnapshotPreferredPageIndex = nil

        let resolvedIndex: Int
        if let preferredPageIndex {
            if preferredPageIndex == Self.chapterEndPageTarget {
                resolvedIndex = max(snapshot.renderData.logicalPages.count - 1, 0)
            } else {
                resolvedIndex = min(max(preferredPageIndex, 0), max(snapshot.renderData.logicalPages.count - 1, 0))
            }
        } else if let anchor, let mappedIndex = snapshot.renderData.index(for: anchor) {
            resolvedIndex = mappedIndex
        } else {
            resolvedIndex = min(max(pageIndex, 0), max(snapshot.renderData.logicalPages.count - 1, 0))
        }

        pageIndex = resolvedIndex
        syncPagerDisplayIndex(animated: animatedSync)
    }

    func flushDeferredSnapshotIfPossible() {
        guard readerInteractionPhase == .idle, !isChapterTransitioning, let deferredSnapshot else { return }
        guard deferredSnapshot.chapterID == currentChapter.id else {
            self.deferredSnapshot = nil
            deferredSnapshotPreferredPageIndex = nil
            return
        }
        commitSnapshot(
            deferredSnapshot,
            preferredPageIndex: deferredSnapshotPreferredPageIndex,
            animatedSync: false
        )
        prefetchAroundCurrentPage()
    }

    func shouldDeferSnapshot(_ snapshot: ReaderContentSnapshot) -> Bool {
        guard let committedSnapshot else { return false }
        guard committedSnapshot.chapterID == snapshot.chapterID else { return false }
        return readerInteractionPhase != .idle || transitionState != nil || isChapterTransitioning
    }
}
