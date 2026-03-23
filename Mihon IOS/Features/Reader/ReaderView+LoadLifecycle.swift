//
//  ReaderView+LoadLifecycle.swift
//  Mihon IOS
//

import SwiftUI

extension ReaderView {
    private static let adjacentChapterPreloadBoundaryDistance = 2

    private var currentChapterResumeProgress: ReadingProgress? {
        guard let progress = model.progress(for: manga), progress.chapterID == currentChapter.id else {
            return nil
        }
        return progress
    }

    func persistProgress() {
        model.updateProgress(for: manga, chapter: currentChapter, pageIndex: pageIndex, totalPages: logicalPages.count)
    }

    func startPageLoad(forceRefresh: Bool) {
        if !forceRefresh, !liveResolvedPages.isEmpty {
            if pageLoadState != .loaded {
                pageLoadState = .loaded
            }
            finalizeResolvedPages()
            return
        }
        let requestID = UUID()
        activeLoadRequestID = requestID
        let chapterSnapshot = currentChapter
        canPersistPageProgress = false
        pageLoadState = .loading
        Task {
            let pages = forceRefresh
                ? await model.retryPages(for: chapterSnapshot, sourceID: manga.sourceID)
                : await model.refreshPages(for: chapterSnapshot, sourceID: manga.sourceID)
            await MainActor.run {
                applyLoadedPages(pages, requestID: requestID, chapterSnapshot: chapterSnapshot, forceRefresh: forceRefresh)
            }
        }
    }

    func applyLoadedPages(_ pages: [ReaderPage], requestID: UUID, chapterSnapshot: Chapter, forceRefresh: Bool) {
        guard requestID == activeLoadRequestID else { return }
        guard chapterSnapshot.id == currentChapter.id else { return }

        if !pages.isEmpty {
            currentChapter = Chapter(
                id: currentChapter.id,
                mangaID: currentChapter.mangaID,
                title: currentChapter.title,
                number: currentChapter.number,
                releaseDate: currentChapter.releaseDate,
                isDownloaded: currentChapter.isDownloaded,
                pages: pages
            )
        }

        if forceRefresh {
            retryTick += 1
        }

        if isChapterTransitioning, liveResolvedPages.isEmpty, recoverFromFailedTransitionIfPossible() {
            return
        }

        pageLoadState = liveResolvedPages.isEmpty ? .failed : .loaded
        if pageLoadState != .loading {
            isChapterTransitioning = false
        }
        finalizeResolvedPages()
    }

    func prefetchAroundCurrentPage() {
        let prefetchCount = effectivePrefetchLookahead(base: model.state.advancedPreferences.imagePrefetchCount)
        guard prefetchCount > 0, let committedSnapshot else {
            prefetchTask?.cancel()
            prefetchTask = Task {
                await imagePipeline.cancelWindow(for: currentChapter.id)
            }
            return
        }

        guard !committedSnapshot.renderData.logicalPages.isEmpty else {
            prefetchTask?.cancel()
            return
        }

        let boundedIndex = min(max(pageIndex, 0), committedSnapshot.renderData.logicalPages.count - 1)
        prefetchTask?.cancel()
        prefetchTask = Task {
            await imagePipeline.updateActiveWindow(
                chapterID: committedSnapshot.chapterID,
                logicalPages: committedSnapshot.renderData.logicalPages,
                currentIndex: boundedIndex,
                lookahead: prefetchCount
            )
        }
    }

    func preloadAdjacentChaptersIfNeeded() {
        guard pageLoadState == .loaded else { return }
        guard !logicalPages.isEmpty else { return }

        let boundaryDistance = min(Self.adjacentChapterPreloadBoundaryDistance, max(logicalPages.count - 1, 0))
        let lastIndex = max(logicalPages.count - 1, 0)

        if pageIndex <= boundaryDistance, let previous = previousChapterForCurrentMode() {
            preloadAdjacentChapterIfNeeded(previous)
        }

        if pageIndex >= max(lastIndex - boundaryDistance, 0), let next = nextChapterForCurrentMode() {
            preloadAdjacentChapterIfNeeded(next)
        }
    }

    func preloadAdjacentChapterIfNeeded(_ chapter: Chapter) {
        if preloadedAdjacentChapterIDs.contains(chapter.id) {
            return
        }
        if adjacentChapterPreloadTasks[chapter.id] != nil {
            return
        }

        let chapterToPreload = chapter
        let task = Task {
            defer {
                Task { @MainActor in
                    adjacentChapterPreloadTasks[chapterToPreload.id] = nil
                }
            }

            guard !Task.isCancelled else { return }
            let pages = await model.refreshPages(for: chapterToPreload, sourceID: manga.sourceID)
            guard !Task.isCancelled else { return }

            if !pages.isEmpty {
                await MainActor.run {
                    preloadedAdjacentChapterIDs.insert(chapterToPreload.id)
                }
            }
        }

        adjacentChapterPreloadTasks[chapter.id] = task
    }

    func recordPrefetchVelocity(for newIndex: Int) {
        let now = Date()
        defer {
            lastPrefetchPageChangeDate = now
            lastPrefetchPageIndex = newIndex
        }

        guard let previousDate = lastPrefetchPageChangeDate else {
            adaptivePrefetchBonus = 0
            return
        }

        let deltaPages = abs(newIndex - lastPrefetchPageIndex)
        guard deltaPages > 0 else { return }

        let elapsed = max(now.timeIntervalSince(previousDate), 0.01)
        let pagesPerSecond = Double(deltaPages) / elapsed

        if pagesPerSecond >= 2.25 {
            adaptivePrefetchBonus = 2
        } else if pagesPerSecond >= 1.1 {
            adaptivePrefetchBonus = 1
        } else if pagesPerSecond <= 0.45 {
            adaptivePrefetchBonus = 0
        }
    }

    func effectivePrefetchLookahead(base: Int) -> Int {
        var lookahead = max(base, 0) + adaptivePrefetchBonus
        if isVerticalReader {
            lookahead += 1
        }
        return min(lookahead, 8)
    }

    func finalizeResolvedPages() {
        let snapshot = buildReaderSnapshot()
        guard !snapshot.renderData.logicalPages.isEmpty else {
            committedSnapshot = snapshot
            canPersistPageProgress = false
            return
        }

        canPersistPageProgress = false
        let targetIndex = pendingPageIndexAfterChapterChange
            ?? (!hasAppliedResumeProgress ? currentChapterResumeProgress?.pageIndex : nil)
            ?? pageIndex
        let boundedIndex = targetIndex == Self.chapterEndPageTarget
            ? max(snapshot.renderData.logicalPages.count - 1, 0)
            : min(max(targetIndex, 0), max(snapshot.renderData.logicalPages.count - 1, 0))
        deferredResumePageIndex = targetIndex == Self.chapterEndPageTarget || targetIndex > boundedIndex ? targetIndex : nil
        hasAppliedResumeProgress = true
        pendingPageIndexAfterChapterChange = nil
        transitionRecoveryContext = nil
        lastPrefetchPageChangeDate = nil
        lastPrefetchPageIndex = boundedIndex
        adaptivePrefetchBonus = 0
        resetTransitionState()
        commitSnapshot(snapshot, preferredPageIndex: targetIndex, animatedSync: false)
        prefetchAroundCurrentPage()
        preloadAdjacentChaptersIfNeeded()
        persistProgress()
        canPersistPageProgress = true
    }

    @discardableResult
    func recoverFromFailedTransitionIfPossible() -> Bool {
        guard let context = transitionRecoveryContext else { return false }
        guard context.chapter.id != currentChapter.id else { return false }

        suppressChapterChangeLifecycle = true
        currentChapter = context.chapter
        pendingPageIndexAfterChapterChange = nil
        activeLoadRequestID = UUID()
        isChapterTransitioning = false
        transitionState = nil
        readerInteractionPhase = .idle
        pagerSettleTask?.cancel()
        pagerSettleTask = nil
        pageImageSizes = context.snapshot?.imageSizes ?? [:]

        if let snapshot = context.snapshot,
           !snapshot.renderData.logicalPages.isEmpty {
            committedSnapshot = snapshot
            deferredSnapshot = nil
            deferredSnapshotPreferredPageIndex = nil
            let boundedIndex = min(max(context.pageIndex, 0), max(snapshot.renderData.logicalPages.count - 1, 0))
            pageIndex = boundedIndex
            pageLoadState = .loaded
            canPersistPageProgress = true
            pageActionResultMessage = "Could not load that chapter. Returned to the previous chapter."
            syncPagerDisplayIndex(animated: false)
            prefetchAroundCurrentPage()
            preloadAdjacentChaptersIfNeeded()
            persistProgress()
        } else {
            committedSnapshot = nil
            pageIndex = 0
            pageLoadState = .failed
            canPersistPageProgress = false
        }

        transitionRecoveryContext = nil
        return true
    }
}
