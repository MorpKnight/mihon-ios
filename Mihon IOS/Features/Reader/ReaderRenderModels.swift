//
//  ReaderRenderModels.swift
//  Mihon IOS
//

import UIKit

struct ReaderContentSnapshot {
    let chapterID: String
    let mode: ReaderMode
    let pages: [ReaderPage]
    let imageSizes: [String: CGSize]
    let renderData: ReaderRenderData
}

enum ReaderInteractionPhase {
    case idle
    case dragging
    case settling
}

struct ReaderRenderData {
    let logicalPages: [ReaderLogicalPage]
    let renderItems: [ReaderRenderItem]

    func anchor(for logicalIndex: Int) -> ReaderLogicalAnchor? {
        guard logicalPages.indices.contains(logicalIndex) else { return nil }
        return logicalPages[logicalIndex].anchor
    }

    func index(for anchor: ReaderLogicalAnchor) -> Int? {
        if let exactIndex = logicalPages.firstIndex(where: { $0.anchor == anchor }) {
            return exactIndex
        }
        return logicalPages.firstIndex(where: { $0.anchor.sourcePageID == anchor.sourcePageID })
    }

    static func build(
        pages: [ReaderPage],
        mode: ReaderMode,
        spreadBehavior: ReaderSpreadBehavior,
        imageSizes: [String: CGSize]
    ) -> ReaderRenderData {
        switch mode {
        case .pagerDefault, .pagerLTR, .pagerRTL:
            return buildPagedData(
                pages: pages,
                mode: mode,
                spreadBehavior: spreadBehavior,
                imageSizes: imageSizes
            )
        case .vertical:
            let logicalPages = pages.enumerated().map { index, page in
                ReaderLogicalPage(
                    id: "\(page.id)|full",
                    sourcePage: page,
                    sourcePageIndex: index,
                    kind: .full
                )
            }
            let renderItems = logicalPages.enumerated().map { index, logicalPage in
                ReaderRenderItem(
                    id: logicalPage.id,
                    logicalPageID: logicalPage.id,
                    logicalPageIndex: index,
                    sourcePageIndex: logicalPage.sourcePageIndex,
                    page: logicalPage.sourcePage,
                    fragment: .full
                )
            }
            return ReaderRenderData(logicalPages: logicalPages, renderItems: renderItems)
        case .webtoon:
            return buildWebtoonData(pages: pages, imageSizes: imageSizes)
        }
    }

    private static func buildPagedData(
        pages: [ReaderPage],
        mode: ReaderMode,
        spreadBehavior: ReaderSpreadBehavior,
        imageSizes: [String: CGSize]
    ) -> ReaderRenderData {
        let logicalPages = pages.enumerated().flatMap { index, page -> [ReaderLogicalPage] in
            let shouldSplit = spreadBehavior == .autoSplit
                && (imageSizes[page.id]?.shouldSplitForSpread ?? false)
            guard shouldSplit else {
                return [
                    ReaderLogicalPage(
                        id: "\(page.id)|full",
                        sourcePage: page,
                        sourcePageIndex: index,
                        kind: .full
                    )
                ]
            }
            return [
                ReaderLogicalPage(
                    id: "\(page.id)|spread-left",
                    sourcePage: page,
                    sourcePageIndex: index,
                    kind: .spreadHalf(.left)
                ),
                ReaderLogicalPage(
                    id: "\(page.id)|spread-right",
                    sourcePage: page,
                    sourcePageIndex: index,
                    kind: .spreadHalf(.right)
                )
            ]
        }

        let baseRenderItems = logicalPages.enumerated().map { index, logicalPage in
            ReaderRenderItem(
                id: logicalPage.id,
                logicalPageID: logicalPage.id,
                logicalPageIndex: index,
                sourcePageIndex: logicalPage.sourcePageIndex,
                page: logicalPage.sourcePage,
                fragment: logicalPage.renderFragment
            )
        }
        let isRTLPager = mode == .pagerDefault || mode == .pagerRTL
        let renderItems = isRTLPager ? Array(baseRenderItems.reversed()) : baseRenderItems
        return ReaderRenderData(logicalPages: logicalPages, renderItems: renderItems)
    }

    private static func buildWebtoonData(
        pages: [ReaderPage],
        imageSizes: [String: CGSize]
    ) -> ReaderRenderData {
        let logicalPages = pages.enumerated().map { index, page in
            ReaderLogicalPage(
                id: "\(page.id)|full",
                sourcePage: page,
                sourcePageIndex: index,
                kind: .full
            )
        }

        let renderItems = logicalPages.enumerated().flatMap { logicalIndex, logicalPage -> [ReaderRenderItem] in
            let slices = imageSizes[logicalPage.sourcePage.id]?.webtoonSliceUnitRects
                ?? [CGRect(x: 0, y: 0, width: 1, height: 1)]
            return slices.enumerated().map { sliceIndex, rect in
                ReaderRenderItem(
                    id: "\(logicalPage.id)|slice-\(sliceIndex)",
                    logicalPageID: logicalPage.id,
                    logicalPageIndex: logicalIndex,
                    sourcePageIndex: logicalPage.sourcePageIndex,
                    page: logicalPage.sourcePage,
                    fragment: slices.count == 1 ? .full : .webtoonSlice(index: sliceIndex, total: slices.count, unitRect: rect)
                )
            }
        }

        return ReaderRenderData(logicalPages: logicalPages, renderItems: renderItems)
    }
}

struct ReaderLogicalPage: Identifiable {
    let id: String
    let sourcePage: ReaderPage
    let sourcePageIndex: Int
    let kind: ReaderLogicalPageKind

    var anchor: ReaderLogicalAnchor {
        ReaderLogicalAnchor(sourcePageID: sourcePage.id, kind: kind.anchorKey)
    }

    var renderFragment: ReaderRenderFragment {
        switch kind {
        case .full:
            return .full
        case .spreadHalf(let side):
            return .spreadHalf(side)
        }
    }
}

enum ReaderLogicalPageKind {
    case full
    case spreadHalf(ReaderSpreadHalf)

    var anchorKey: String {
        switch self {
        case .full:
            return "full"
        case .spreadHalf(let side):
            return "spread-\(side.rawValue)"
        }
    }
}

struct ReaderLogicalAnchor: Equatable {
    let sourcePageID: String
    let kind: String
}

struct ReaderRenderItem: Identifiable {
    let id: String
    let logicalPageID: String
    let logicalPageIndex: Int
    let sourcePageIndex: Int
    let page: ReaderPage
    let fragment: ReaderRenderFragment
}

enum ReaderRenderFragment {
    case full
    case spreadHalf(ReaderSpreadHalf)
    case webtoonSlice(index: Int, total: Int, unitRect: CGRect)
}

enum ReaderSpreadHalf: String {
    case left
    case right

    var unitRect: CGRect {
        switch self {
        case .left:
            return CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .right:
            return CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        }
    }
}

extension CGSize {
    static let readerSpreadSplitThreshold: CGFloat = 1.32
    static let readerWebtoonSliceHeight: CGFloat = 4_096

    var shouldSplitForSpread: Bool {
        width > 0 && height > 0 && (width / height) >= Self.readerSpreadSplitThreshold
    }

    var webtoonSliceUnitRects: [CGRect] {
        guard width > 0, height > 0, height > Self.readerWebtoonSliceHeight else {
            return [CGRect(x: 0, y: 0, width: 1, height: 1)]
        }

        let sliceCount = Int(ceil(height / Self.readerWebtoonSliceHeight))
        guard sliceCount > 1 else {
            return [CGRect(x: 0, y: 0, width: 1, height: 1)]
        }

        let normalizedSliceHeight = 1 / CGFloat(sliceCount)
        return (0..<sliceCount).map { index in
            let originY = CGFloat(index) * normalizedSliceHeight
            let height = index == sliceCount - 1 ? 1 - originY : normalizedSliceHeight
            return CGRect(x: 0, y: originY, width: 1, height: height)
        }
    }

    func aspectFit(in boundingSize: CGSize) -> CGSize {
        guard width > 0, height > 0, boundingSize.width > 0, boundingSize.height > 0 else {
            return .zero
        }
        let scale = min(boundingSize.width / width, boundingSize.height / height)
        return CGSize(width: width * scale, height: height * scale)
    }
}

extension UIImage {
    func cropped(unitRect: CGRect) -> UIImage? {
        guard let cgImage else { return nil }
        let pixelRect = CGRect(
            x: unitRect.origin.x * CGFloat(cgImage.width),
            y: unitRect.origin.y * CGFloat(cgImage.height),
            width: unitRect.size.width * CGFloat(cgImage.width),
            height: unitRect.size.height * CGFloat(cgImage.height)
        ).integral

        guard pixelRect.width > 0, pixelRect.height > 0 else { return nil }
        guard let cropped = cgImage.cropping(to: pixelRect) else { return nil }
        return UIImage(cgImage: cropped, scale: scale, orientation: imageOrientation)
    }
}
