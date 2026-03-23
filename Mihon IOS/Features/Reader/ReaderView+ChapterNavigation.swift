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
            } else {
                syncPagerDisplayIndex(animated: true)
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
            } else {
                syncPagerDisplayIndex(animated: true)
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
            withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.86, blendDuration: 0.12)) {
                transitionState = nil
            }
        }
    }

    func confirmChapterTransition(_ direction: ReaderTransitionDirection) {
        if isNavigationSuspended {
            model.appendDiagnostic(
                kind: .stateTransition,
                severity: .warning,
                title: "Reader Transition Blocked",
                message: "Chapter transition was requested while navigation was suspended.",
                errorCode: DiagnosticErrorCode.rdrTransitionBlocked.rawValue,
                module: "ReaderNavigation",
                metadata: ["direction": direction == .previous ? "previous" : "next"]
            )
            return
        }
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
            model.appendDiagnostic(
                kind: .stateTransition,
                severity: .error,
                title: "Chapter Transition Failed",
                message: "No target chapter found for transition direction: \(direction == .previous ? "previous" : "next").",
                errorCode: DiagnosticErrorCode.rdrInvalidChapter.rawValue,
                module: "ReaderNavigation"
            )
            return
        }
        model.appendDiagnostic(
            kind: .stateTransition,
            severity: .info,
            title: "Reader Transition Started",
            message: "Chapter transition has started.",
            errorCode: DiagnosticErrorCode.rdrTransitionStarted.rawValue,
            module: "ReaderNavigation",
            metadata: [
                "direction": direction == .previous ? "previous" : "next",
                "targetChapter": targetChapter.title,
                "targetPage": direction == .previous ? "last" : "first"
            ]
        )
        withAnimation(.easeOut(duration: 0.2)) {
            transitionState = ReaderTransitionState(direction: direction, progress: 1, isLoading: true)
        }
        transitionToChapter(targetChapter, pageIndex: targetPageIndex)
    }
}
