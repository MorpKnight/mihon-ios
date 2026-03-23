//
//  ReaderView+VerticalScroll.swift
//  Mihon IOS
//

import SwiftUI

extension ReaderView {
    private static let verticalBoundaryOverscrollTolerance: CGFloat = 14

    func pageAnchorID(for index: Int) -> String {
        "\(retryTick)-\(currentChapter.id)-\(index)"
    }

    func scrollToCurrentPage(using proxy: ScrollViewProxy, animated: Bool) {
        guard isVerticalReader, pageLoadState == .loaded, !verticalRenderItems.isEmpty else { return }
        guard let firstRenderIndex = verticalRenderItems.firstIndex(where: { $0.logicalPageIndex == boundedPageIndex(for: pageIndex) }) else {
            return
        }
        let action = {
            proxy.scrollTo(pageAnchorID(for: firstRenderIndex), anchor: .top)
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.2), action)
        } else {
            action()
        }
    }

    func updateVerticalPageIndex(from frames: [Int: CGRect], viewportHeight: CGFloat) {
        guard isVerticalReader, pageLoadState == .loaded, !frames.isEmpty else { return }
        updateVerticalBoundaryReadiness(from: frames, viewportHeight: viewportHeight)

        let viewport = CGRect(x: 0, y: 0, width: 1, height: viewportHeight)
        let visibleFrames = frames.filter { _, frame in
            !frame.intersection(viewport).isNull
        }
        guard !visibleFrames.isEmpty else { return }

        let selectedIndex: Int?
        if let coveringTop = visibleFrames
            .filter({ _, frame in frame.minY <= 1 && frame.maxY > 1 })
            .min(by: { lhs, rhs in lhs.key < rhs.key }) {
            selectedIndex = coveringTop.key
        } else {
            selectedIndex = visibleFrames.min(by: { lhs, rhs in
                if lhs.value.minY == rhs.value.minY {
                    return lhs.key < rhs.key
                }
                return lhs.value.minY < rhs.value.minY
            })?.key
        }

        guard let selectedIndex else { return }
        guard verticalRenderItems.indices.contains(selectedIndex) else { return }
        let logicalIndex = boundedPageIndex(for: verticalRenderItems[selectedIndex].logicalPageIndex)
        if logicalIndex != pageIndex {
            pageIndex = logicalIndex
        }
    }

    func updateVerticalBoundaryReadiness(from frames: [Int: CGRect], viewportHeight: CGFloat) {
        guard !verticalRenderItems.isEmpty else {
            verticalBoundaryCanLoadPrevious = false
            verticalBoundaryCanLoadNext = false
            return
        }

        let firstRenderIndex = 0
        let lastRenderIndex = verticalRenderItems.count - 1
        guard let firstFrame = frames[firstRenderIndex], let lastFrame = frames[lastRenderIndex] else {
            verticalBoundaryCanLoadPrevious = false
            verticalBoundaryCanLoadNext = false
            return
        }

        let topReady = firstFrame.minY >= -Self.verticalBoundaryOverscrollTolerance
        let bottomReady = lastFrame.maxY <= viewportHeight + Self.verticalBoundaryOverscrollTolerance

        if verticalBoundaryCanLoadPrevious != topReady {
            verticalBoundaryCanLoadPrevious = topReady
        }
        if verticalBoundaryCanLoadNext != bottomReady {
            verticalBoundaryCanLoadNext = bottomReady
        }
    }
}
