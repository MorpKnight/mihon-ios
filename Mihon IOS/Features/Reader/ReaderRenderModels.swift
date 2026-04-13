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
        imageSizes: [String: CGSize],
        pagerViewportSize: CGSize? = nil
    ) -> ReaderRenderData {
        switch mode {
        case .pagerDefault, .pagerLTR, .pagerRTL:
            return buildPagedData(
                pages: pages,
                mode: mode,
                spreadBehavior: spreadBehavior,
                imageSizes: imageSizes,
                pagerViewportSize: pagerViewportSize
            )
        case .vertical:
            let logicalPages = pages.enumerated().map { index, page in
                ReaderLogicalPage(
                    id: "\(page.id)|full",
                    sourcePage: page,
                    sourcePageIndex: index,
                    anchorKey: "full",
                    renderFragment: .full
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
        imageSizes: [String: CGSize],
        pagerViewportSize: CGSize?
    ) -> ReaderRenderData {
        let pageGroups = pages.enumerated().flatMap { index, page -> [[ReaderLogicalPage]] in
            let shouldSplit = spreadBehavior == .autoSplit
                && (imageSizes[page.id]?.shouldSplitForSpread ?? false)
            let baseFragments: [PagedFragmentDescriptor]
            if shouldSplit {
                baseFragments = [
                    PagedFragmentDescriptor(
                        idSuffix: "spread-left",
                        anchorKey: "spread-left",
                        renderFragment: .spreadHalf(.left),
                        cropRect: ReaderSpreadHalf.left.unitRect
                    ),
                    PagedFragmentDescriptor(
                        idSuffix: "spread-right",
                        anchorKey: "spread-right",
                        renderFragment: .spreadHalf(.right),
                        cropRect: ReaderSpreadHalf.right.unitRect
                    )
                ]
            } else {
                baseFragments = [
                    PagedFragmentDescriptor(
                        idSuffix: "full",
                        anchorKey: "full",
                        renderFragment: .full,
                        cropRect: CGRect(x: 0, y: 0, width: 1, height: 1)
                    )
                ]
            }

            return baseFragments.map { descriptor in
                buildPagedLogicalPageGroup(
                    page: page,
                    sourcePageIndex: index,
                    descriptor: descriptor,
                    imageSize: imageSizes[page.id],
                    pagerViewportSize: pagerViewportSize
                )
            }
        }

        let logicalPages = pageGroups.flatMap { $0 }
        let logicalIndexByID = Dictionary(uniqueKeysWithValues: logicalPages.enumerated().map { ($1.id, $0) })
        let renderGroups = (mode == .pagerDefault || mode == .pagerRTL) ? Array(pageGroups.reversed()) : pageGroups
        let renderItems = renderGroups.flatMap { group in
            group.compactMap { logicalPage -> ReaderRenderItem? in
                guard let logicalIndex = logicalIndexByID[logicalPage.id] else { return nil }
                return ReaderRenderItem(
                    id: logicalPage.id,
                    logicalPageID: logicalPage.id,
                    logicalPageIndex: logicalIndex,
                    sourcePageIndex: logicalPage.sourcePageIndex,
                    page: logicalPage.sourcePage,
                    fragment: logicalPage.renderFragment
                )
            }
        }
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
                anchorKey: "full",
                renderFragment: .full
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
                    fragment: slices.count == 1 ? .full : .slice(index: sliceIndex, total: slices.count, unitRect: rect)
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
    let anchorKey: String
    let renderFragment: ReaderRenderFragment

    var anchor: ReaderLogicalAnchor {
        ReaderLogicalAnchor(sourcePageID: sourcePage.id, kind: anchorKey)
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
    case slice(index: Int, total: Int, unitRect: CGRect)
}

private struct PagedFragmentDescriptor {
    let idSuffix: String
    let anchorKey: String
    let renderFragment: ReaderRenderFragment
    let cropRect: CGRect
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

    func applyingCrop(_ cropRect: CGRect) -> CGSize {
        CGSize(width: width * cropRect.width, height: height * cropRect.height)
    }
}

private extension ReaderRenderData {
    static func buildPagedLogicalPageGroup(
        page: ReaderPage,
        sourcePageIndex: Int,
        descriptor: PagedFragmentDescriptor,
        imageSize: CGSize?,
        pagerViewportSize: CGSize?
    ) -> [ReaderLogicalPage] {
        let sliceRects = pagedSliceUnitRects(
            page: page,
            imageSize: imageSize,
            cropRect: descriptor.cropRect,
            pagerViewportSize: pagerViewportSize
        )
        guard sliceRects.count > 1 else {
            return [
                ReaderLogicalPage(
                    id: "\(page.id)|\(descriptor.idSuffix)",
                    sourcePage: page,
                    sourcePageIndex: sourcePageIndex,
                    anchorKey: descriptor.anchorKey,
                    renderFragment: descriptor.renderFragment
                )
            ]
        }

        return sliceRects.enumerated().map { index, rect in
            ReaderLogicalPage(
                id: "\(page.id)|\(descriptor.idSuffix)|slice-\(index)",
                sourcePage: page,
                sourcePageIndex: sourcePageIndex,
                anchorKey: "\(descriptor.anchorKey)|slice-\(index)",
                renderFragment: .slice(index: index, total: sliceRects.count, unitRect: rect)
            )
        }
    }

    static func pagedSliceUnitRects(
        page: ReaderPage,
        imageSize: CGSize?,
        cropRect: CGRect,
        pagerViewportSize: CGSize?
    ) -> [CGRect] {
        guard page.assetKind == .image else { return [cropRect] }
        guard let imageSize, imageSize.width > 0, imageSize.height > 0 else { return [cropRect] }
        guard let pagerViewportSize, pagerViewportSize.width > 0, pagerViewportSize.height > 0 else { return [cropRect] }

        let croppedSize = imageSize.applyingCrop(cropRect)
        guard croppedSize.width > 0, croppedSize.height > 0 else { return [cropRect] }

        let fittedHeight = pagerViewportSize.width * (croppedSize.height / croppedSize.width)
        guard fittedHeight > pagerViewportSize.height * 1.01 else { return [cropRect] }

        let visibleNormalizedHeight = min(max(pagerViewportSize.height / fittedHeight, 0.01), 1)
        let sliceCount = Int(ceil(1 / visibleNormalizedHeight))
        guard sliceCount > 1 else { return [cropRect] }

        return (0..<sliceCount).map { index in
            let localOriginY = CGFloat(index) * visibleNormalizedHeight
            let localHeight = index == sliceCount - 1 ? max(1 - localOriginY, 0) : visibleNormalizedHeight
            return CGRect(
                x: cropRect.minX,
                y: cropRect.minY + cropRect.height * localOriginY,
                width: cropRect.width,
                height: cropRect.height * localHeight
            )
        }.filter { $0.width > 0 && $0.height > 0 }
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
