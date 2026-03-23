//
//  ReaderView+ChapterNavigation.swift
//  Mihon IOS
//

import SwiftUI

extension ReaderView {
    func handleTransitionTap(intent: ReaderTapIntent, transitionDirection: ReaderTransitionDirection) {
        switch intent {
        case .toggleChrome:
            toggleChrome()
        case .forward:
            if transitionDirection == .next {
                confirmChapterTransition(.next)
            } else {
                returnFromTransitionOverlay()
            }
        case .backward:
            if transitionDirection == .previous {
                confirmChapterTransition(.previous)
            } else {
                returnFromTransitionOverlay()
            }
        case .none:
            break
        }
    }

    func returnFromTransitionOverlay() {
        resetTransitionState()
        syncPagerDisplayIndex(animated: true)
    }

    func advancePageForward() {
        if pageIndex + 1 < logicalPages.count {
            let newIndex = pageIndex + 1
            pageIndex = newIndex
            if isVerticalReader {
                pendingVerticalScrollTarget = newIndex
            }
            return
        }
        if isVerticalReader {
            return
        }
        if let index = pagerTransitionIndex(for: .next) {
            pagerDisplayIndex = index
            resetTransitionState()
        }
    }

    func advancePageBackward() {
        if pageIndex > 0 {
            let newIndex = pageIndex - 1
            pageIndex = newIndex
            if isVerticalReader {
                pendingVerticalScrollTarget = newIndex
            }
            return
        }
        if isVerticalReader {
            return
        }
        if let index = pagerTransitionIndex(for: .previous) {
            pagerDisplayIndex = index
            resetTransitionState()
        }
    }

    func nextChapterForCurrentMode() -> Chapter? {
        model.nextChapter(after: currentChapter, in: manga)
    }

    func previousChapterForCurrentMode() -> Chapter? {
        model.previousChapter(before: currentChapter, in: manga)
    }

    func transitionToChapter(_ chapter: Chapter, pageIndex targetPageIndex: Int) {
        transitionRecoveryContext = ReaderTransitionRecoveryContext(
            chapter: currentChapter,
            pageIndex: pageIndex,
            snapshot: committedSnapshot
        )
        canPersistPageProgress = false
        pendingPageIndexAfterChapterChange = targetPageIndex
        pageLoadState = .idle
        isChapterTransitioning = true
        transitionState = nil
        readerInteractionPhase = .idle
        pagerSettleTask?.cancel()
        pagerSettleTask = nil
        currentChapter = chapter
    }

    func lastPageIndex(for chapter: Chapter) -> Int {
        if chapter.id == currentChapter.id {
            return max(logicalPages.count - 1, 0)
        }
        if !chapter.pages.isEmpty {
            return max(chapter.pages.count - 1, 0)
        }
        if let cached = model.chapters(for: manga).first(where: { $0.id == chapter.id }) {
            return max(cached.pages.count - 1, 0)
        }
        return 0
    }

    func pagerTransitionIndex(for direction: ReaderTransitionDirection) -> Int? {
        pagerItems.firstIndex { item in
            switch (direction, item) {
            case (.previous, .previousChapter), (.next, .nextChapter):
                return true
            default:
                return false
            }
        }
    }

    func updateTransitionProgress(for direction: ReaderTransitionDirection, translationMagnitude: CGFloat) {
        let progress = min(max(translationMagnitude / ReaderTransitionState.activationDistance, 0), 1)
        transitionState = ReaderTransitionState(direction: direction, progress: progress, isLoading: false)
    }

    func transitionProgress(for direction: ReaderTransitionDirection) -> CGFloat {
        guard transitionState?.direction == direction else { return 0 }
        return transitionState?.progress ?? 0
    }

    func resetTransitionState() {
        if !isChapterTransitioning {
            transitionState = nil
        }
    }

    func confirmChapterTransition(_ direction: ReaderTransitionDirection) {
        guard !isNavigationSuspended else { return }
        let targetChapter: Chapter?
        let targetPageIndex: Int

        switch direction {
        case .previous:
            targetChapter = previousChapterForCurrentMode()
            targetPageIndex = Self.chapterEndPageTarget
        case .next:
            targetChapter = nextChapterForCurrentMode()
            targetPageIndex = 0
        }

        guard let targetChapter else {
            resetTransitionState()
            syncPagerDisplayIndex(animated: true)
            return
        }
        transitionState = ReaderTransitionState(direction: direction, progress: 1, isLoading: true)
        transitionToChapter(targetChapter, pageIndex: targetPageIndex)
    }
}
