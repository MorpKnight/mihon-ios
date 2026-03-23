//
//  ReaderView+ComputedState.swift
//  Mihon IOS
//

import SwiftUI

extension ReaderView {
    var liveResolvedPages: [ReaderPage] {
        let resolved = model.resolvedChapter(currentChapter)
        return resolved.pages.isEmpty ? currentChapter.pages : resolved.pages
    }

    var currentPages: [ReaderPage] {
        committedSnapshot?.pages ?? []
    }

    var activeReaderMode: ReaderMode {
        committedSnapshot?.mode ?? model.state.readerPreferences.mode
    }

    var isVerticalReader: Bool {
        activeReaderMode == .vertical || activeReaderMode == .webtoon
    }

    var isWebtoonMode: Bool {
        activeReaderMode == .webtoon
    }

    var isNavigationSuspended: Bool {
        isChapterTransitioning || pageLoadState == .loading
    }

    var transitionDirection: ReaderTransitionDirection? {
        transitionState?.direction
    }

    private var readerRenderData: ReaderRenderData {
        committedSnapshot?.renderData ?? ReaderRenderData(logicalPages: [], renderItems: [])
    }

    var logicalPages: [ReaderLogicalPage] {
        readerRenderData.logicalPages
    }

    var verticalRenderItems: [ReaderRenderItem] {
        readerRenderData.renderItems
    }

    private var pagerRenderItems: [ReaderRenderItem] {
        readerRenderData.renderItems
    }

    var hasPreviousChapter: Bool {
        previousChapterForCurrentMode() != nil
    }

    var hasNextChapter: Bool {
        nextChapterForCurrentMode() != nil
    }

    var pagerItems: [ReaderPagerItem] {
        var items: [ReaderPagerItem] = []
        if isRTLPager {
            if hasNextChapter {
                items.append(.nextChapter)
            }
            items.append(contentsOf: pagerRenderItems.map(ReaderPagerItem.render))
            if hasPreviousChapter {
                items.append(.previousChapter)
            }
        } else {
            if hasPreviousChapter {
                items.append(.previousChapter)
            }
            items.append(contentsOf: pagerRenderItems.map(ReaderPagerItem.render))
            if hasNextChapter {
                items.append(.nextChapter)
            }
        }
        return items
    }

    var currentPagerInteractionState: ReaderInteractionState {
        guard pagerItems.indices.contains(pagerDisplayIndex) else { return .default }
        guard case .render(let item) = pagerItems[pagerDisplayIndex] else { return .default }
        return surfaceInteractionStates[item.id] ?? .default
    }

    var currentPagerTransitionDirection: ReaderTransitionDirection? {
        guard !isVerticalReader else { return nil }
        guard pagerItems.indices.contains(pagerDisplayIndex) else { return nil }
        switch pagerItems[pagerDisplayIndex] {
        case .previousChapter:
            return .previous
        case .nextChapter:
            return .next
        case .render:
            return nil
        }
    }

    var isRTLPager: Bool {
        switch activeReaderMode {
        case .pagerDefault, .pagerRTL:
            return true
        case .pagerLTR, .vertical, .webtoon:
            return false
        }
    }
}
