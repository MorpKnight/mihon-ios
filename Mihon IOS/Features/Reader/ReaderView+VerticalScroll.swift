//
//  ReaderView+VerticalScroll.swift
//  Mihon IOS
//

import SwiftUI

extension ReaderView {
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
        let viewport = CGRect(x: 0, y: 0, width: 1, height: viewportHeight)
        let visibleFrames = frames.filter { _, frame in
            !frame.intersection(viewport).isNull
        }

        if visibleFrames.isEmpty {
            // When the transition page is fully in view, reader render items can be out of viewport.
            // Pin pageIndex to the nearest boundary so drag-to-transition remains responsive.
            if let lastOffset = frames.keys.max(),
               let lastFrame = frames[lastOffset],
               lastFrame.maxY <= 1,
               let lastLogicalPage = verticalRenderItems.last?.logicalPageIndex {
                let boundedLast = boundedPageIndex(for: lastLogicalPage)
                if boundedLast != pageIndex {
                    pageIndex = boundedLast
                }
                return
            }

            if let firstOffset = frames.keys.min(),
               let firstFrame = frames[firstOffset],
               firstFrame.minY >= viewportHeight - 1,
               pageIndex != 0 {
                pageIndex = 0
            }
            return
        }

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
}
