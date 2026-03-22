//
//  ReaderView+LoadLifecycle.swift
//  Mihon IOS
//

import SwiftUI

extension ReaderView {
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

        pageLoadState = liveResolvedPages.isEmpty ? .failed : .loaded
        if pageLoadState != .loading {
            isChapterTransitioning = false
        }
        finalizeResolvedPages()
    }

    func prefetchAroundCurrentPage() {
        let prefetchCount = model.state.advancedPreferences.imagePrefetchCount
        guard prefetchCount > 0, let committedSnapshot else {
            prefetchTask?.cancel()
            prefetchTask = Task {
                await imagePipeline.cancelWindow(for: currentChapter.id)
            }
            return
        }
        prefetchTask?.cancel()
        prefetchTask = Task {
            await imagePipeline.updateActiveWindow(
                chapterID: committedSnapshot.chapterID,
                logicalPages: committedSnapshot.renderData.logicalPages,
                currentIndex: pageIndex,
                lookahead: prefetchCount
            )
        }
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
        resetTransitionState()
        commitSnapshot(snapshot, preferredPageIndex: targetIndex, animatedSync: false)
        prefetchAroundCurrentPage()
        persistProgress()
        canPersistPageProgress = true
    }
}
