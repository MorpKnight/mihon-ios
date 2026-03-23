//
//  ReaderView+PagerInteraction.swift
//  Mihon IOS
//

import SwiftUI

extension ReaderView {
    func pagerDisplayIndex(for actualIndex: Int) -> Int {
        let boundedActualIndex = boundedPageIndex(for: actualIndex)
        if let renderIndex = pagerItems.firstIndex(where: { item in
            guard case .render(let renderItem) = item else { return false }
            return renderItem.logicalPageIndex == boundedActualIndex
        }) {
            return renderIndex
        }

        return pagerItems.firstIndex(where: { item in
            if case .render = item {
                return true
            }
            return false
        }) ?? 0
    }

    func syncPagerDisplayIndex(animated: Bool) {
        guard !isVerticalReader else { return }
        let targetIndex = pagerDisplayIndex(for: pageIndex)
        guard targetIndex != pagerDisplayIndex else { return }
        if animated {
            beginPagerSettling()
            withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.9)) {
                pagerDisplayIndex = targetIndex
            }
        } else {
            pagerDisplayIndex = targetIndex
        }
    }

    func handlePagerDisplayIndexChange(_ newIndex: Int) {
        guard pagerItems.indices.contains(newIndex) else { return }
        switch pagerItems[newIndex] {
        case .render(let renderItem):
            if renderItem.logicalPageIndex != pageIndex {
                pageIndex = renderItem.logicalPageIndex
            }
        case .previousChapter, .nextChapter:
            break
        }
    }

    var canRouteTapPageTurn: Bool {
        if currentPagerTransitionDirection != nil {
            return false
        }
        return !currentPagerInteractionState.consumesTapNavigation
    }

    var allowsInteractivePagerDragging: Bool {
        if currentPagerTransitionDirection != nil {
            return true
        }
        if currentPagerInteractionState.scale <= 1.01 {
            return true
        }
        return !currentPagerInteractionState.readyDirections.isEmpty
    }

    func isForwardPagerTranslation(_ translationWidth: CGFloat) -> Bool {
        isRTLPager ? translationWidth > 0 : translationWidth < 0
    }

    func stepPager(movingLeft: Bool) {
        beginPagerSettling()
        let nextIndex = min(max(pagerDisplayIndex + (movingLeft ? 1 : -1), 0), max(pagerItems.count - 1, 0))
        guard nextIndex != pagerDisplayIndex else { return }
        pagerDisplayIndex = nextIndex
        handlePagerDisplayIndexChange(nextIndex)
        resetTransitionState()
    }

    func handlePagerDragChanged(translationWidth: CGFloat) {
        guard !isNavigationSuspended else { return }
        if abs(translationWidth) > 0 {
            readerInteractionPhase = .dragging
        }
        guard let direction = currentPagerTransitionDirection else {
            if transitionDirection != nil {
                resetTransitionState()
            }
            return
        }

        let translationMagnitude: CGFloat
        switch direction {
        case .next:
            translationMagnitude = isForwardPagerTranslation(translationWidth) ? abs(translationWidth) : 0
        case .previous:
            translationMagnitude = isForwardPagerTranslation(translationWidth) ? 0 : abs(translationWidth)
        }

        if translationMagnitude > 0 {
            updateTransitionProgress(for: direction, translationMagnitude: translationMagnitude)
        } else if transitionDirection != nil {
            resetTransitionState()
        }
    }

    func shouldCapturePagerDrag(translationWidth: CGFloat, translationHeight: CGFloat) -> Bool {
        guard abs(translationWidth) > abs(translationHeight) else { return false }
        guard allowsInteractivePagerDragging else { return false }

        if currentPagerInteractionState.scale <= 1.01 {
            return true
        }

        let dragDirection: ReaderPanEdgeState = translationWidth < 0 ? .leftDrag : .rightDrag
        return currentPagerInteractionState.readyDirections.contains(dragDirection)
    }

    func handlePagerDragEnded(
        translationWidth: CGFloat,
        predictedTranslationWidth: CGFloat,
        containerWidth: CGFloat
    ) {
        guard !isNavigationSuspended else { return }
        let threshold = max(containerWidth * 0.18, 48)
        let shouldMove = abs(translationWidth) > threshold || abs(predictedTranslationWidth) > containerWidth * 0.32
        guard shouldMove else {
            settlePagerInteraction()
            resetTransitionState()
            return
        }

        let movingLeft = translationWidth < 0

        if let transitionDirection = currentPagerTransitionDirection {
            if transitionProgress(for: transitionDirection) >= 1 {
                confirmChapterTransition(transitionDirection)
                return
            }
            stepPager(movingLeft: movingLeft)
            return
        }

        if currentPagerInteractionState.scale > 1.01 {
            let dragDirection: ReaderPanEdgeState = movingLeft ? .leftDrag : .rightDrag
            guard currentPagerInteractionState.readyDirections.contains(dragDirection) else { return }
        }

        stepPager(movingLeft: movingLeft)
    }

    func beginPagerSettling() {
        readerInteractionPhase = .settling
        settlePagerInteraction()
    }

    func settlePagerInteraction() {
        readerInteractionPhase = .settling
        pagerSettleTask?.cancel()
        pagerSettleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard !Task.isCancelled else { return }
            readerInteractionPhase = .idle
            flushDeferredSnapshotIfPossible()
        }
    }
}
