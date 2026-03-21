//
//  ReaderTiledPageView.swift
//  Mihon IOS
//

import CoreImage
import SwiftUI
import UIKit

struct ReaderImageAssetSource: Equatable, Hashable {
    let cacheKey: String
    let remoteURL: URL?
    let localFileURL: URL?
}

struct ReaderPageViewportState: Equatable {
    let scale: CGFloat
    let contentOffset: CGPoint
    let isLeftEdgeReadyForPageTurn: Bool
    let isRightEdgeReadyForPageTurn: Bool
}

struct ReaderColorTransform: Equatable, Hashable {
    let enabled: Bool
    let grayscale: Double
    let dimming: Double

    init(filter: ReaderColorFilter) {
        enabled = filter.enabled
        grayscale = filter.grayscale
        dimming = filter.dimming
    }

    var cacheKey: String {
        guard enabled else { return "off" }
        return "g\(Int((grayscale * 100).rounded()))-d\(Int((dimming * 100).rounded()))"
    }
}

struct ReaderPreviewImageResult {
    let image: UIImage
    let sourcePixelSize: CGSize
}

struct ReaderTileCacheKey: Hashable {
    let sourceKey: String
    let cropRect: CGRect
    let targetPixelSize: CGSize
    let transformKey: String
}

struct ReaderTileRequest: Hashable {
    let source: ReaderImageAssetSource
    let normalizedCropRect: CGRect
    let targetPixelSize: CGSize
    let colorTransform: ReaderColorTransform

    var cacheKey: ReaderTileCacheKey {
        ReaderTileCacheKey(
            sourceKey: source.cacheKey,
            cropRect: normalizedCropRect,
            targetPixelSize: targetPixelSize,
            transformKey: colorTransform.cacheKey
        )
    }
}

struct ReaderTiledPageSurface: UIViewRepresentable {
    let source: ReaderImageAssetSource
    let variantKey: String
    let normalizedCropRect: CGRect
    let colorTransform: ReaderColorTransform
    let allowsZoom: Bool
    let retryToken: Int
    let onSourceSizeResolved: (CGSize) -> Void
    let onViewportStateChanged: (ReaderPageViewportState) -> Void
    let onFailureChanged: (String?) -> Void

    func makeUIView(context: Context) -> ReaderTiledPageHostView {
        let view = ReaderTiledPageHostView()
        view.onSourceSizeResolved = onSourceSizeResolved
        view.onViewportStateChanged = onViewportStateChanged
        view.onFailureChanged = onFailureChanged
        view.apply(
            configuration: .init(
                source: source,
                variantKey: variantKey,
                normalizedCropRect: normalizedCropRect,
                colorTransform: colorTransform,
                allowsZoom: allowsZoom,
                retryToken: retryToken
            )
        )
        return view
    }

    func updateUIView(_ uiView: ReaderTiledPageHostView, context: Context) {
        uiView.onSourceSizeResolved = onSourceSizeResolved
        uiView.onViewportStateChanged = onViewportStateChanged
        uiView.onFailureChanged = onFailureChanged
        uiView.apply(
            configuration: .init(
                source: source,
                variantKey: variantKey,
                normalizedCropRect: normalizedCropRect,
                colorTransform: colorTransform,
                allowsZoom: allowsZoom,
                retryToken: retryToken
            )
        )
    }
}

@MainActor
final class ReaderTiledPageHostView: UIView, UIScrollViewDelegate {
    struct Configuration: Equatable {
        let source: ReaderImageAssetSource
        let variantKey: String
        let normalizedCropRect: CGRect
        let colorTransform: ReaderColorTransform
        let allowsZoom: Bool
        let retryToken: Int
    }

    var onSourceSizeResolved: ((CGSize) -> Void)?
    var onViewportStateChanged: ((ReaderPageViewportState) -> Void)?
    var onFailureChanged: ((String?) -> Void)?

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let previewImageView = UIImageView()
    private let tileOverlayView = UIView()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)

    private var configuration: Configuration?
    private var previewTask: Task<Void, Never>?
    private var tileTasks: [ReaderTileCacheKey: Task<Void, Never>] = [:]
    private var tileViews: [ReaderTileCacheKey: UIImageView] = [:]
    private var croppedSourcePixelSize: CGSize = .zero
    private var currentGeneration = UUID()
    private var didArmLeftPageTurn = false
    private var didArmRightPageTurn = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit {
        previewTask?.cancel()
        tileTasks.values.forEach { $0.cancel() }
    }

    func apply(configuration: Configuration) {
        let needsFullReload = self.configuration?.source != configuration.source
            || self.configuration?.variantKey != configuration.variantKey
            || self.configuration?.normalizedCropRect != configuration.normalizedCropRect
            || self.configuration?.colorTransform != configuration.colorTransform
            || self.configuration?.allowsZoom != configuration.allowsZoom
            || self.configuration?.retryToken != configuration.retryToken

        self.configuration = configuration
        if needsFullReload {
            reload()
        } else {
            configureZoom()
            layoutContentIfPossible()
            publishViewportState()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        loadingIndicator.center = CGPoint(x: bounds.midX, y: bounds.midY)
        if configuration != nil, bounds.width > 0, bounds.height > 0, previewImageView.image == nil, previewTask == nil {
            reload()
        }
        layoutContentIfPossible()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        configuration?.allowsZoom == true ? contentView : nil
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContentIfNeeded()
        updateVisibleTiles()
        publishViewportState()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.zoomScale <= 1.01 {
            didArmLeftPageTurn = false
            didArmRightPageTurn = false
        }
        updateVisibleTiles()
        publishViewportState()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        armEdgeTurnIfNeeded()
        publishViewportState()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        armEdgeTurnIfNeeded()
        publishViewportState()
    }

    private func setup() {
        backgroundColor = .clear

        scrollView.delegate = self
        scrollView.backgroundColor = .clear
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.bounces = true
        addSubview(scrollView)

        contentView.backgroundColor = .clear
        scrollView.addSubview(contentView)

        previewImageView.backgroundColor = .clear
        previewImageView.contentMode = .scaleToFill
        previewImageView.clipsToBounds = true
        contentView.addSubview(previewImageView)

        tileOverlayView.backgroundColor = .clear
        contentView.addSubview(tileOverlayView)

        loadingIndicator.hidesWhenStopped = true
        addSubview(loadingIndicator)
    }

    private func reload() {
        previewTask?.cancel()
        previewTask = nil
        tileTasks.values.forEach { $0.cancel() }
        tileTasks.removeAll()
        tileViews.values.forEach { $0.removeFromSuperview() }
        tileViews.removeAll()
        previewImageView.image = nil
        croppedSourcePixelSize = .zero
        didArmLeftPageTurn = false
        didArmRightPageTurn = false
        currentGeneration = UUID()
        configureZoom()
        onFailureChanged?(nil)
        loadingIndicator.startAnimating()

        guard let configuration else { return }
        guard bounds.width > 0, bounds.height > 0 else { return }
        let generation = currentGeneration
        let maxPreviewPixels = max(bounds.width, bounds.height, 1) * UIScreen.main.scale * 1.5
        previewTask = Task { [weak self] in
            guard let self else { return }
            do {
                let preview = try await ReaderImagePipeline.shared.previewImage(
                    for: configuration.source,
                    variantKey: configuration.variantKey,
                    normalizedCropRect: configuration.normalizedCropRect,
                    maxPixelSize: maxPreviewPixels,
                    colorTransform: configuration.colorTransform,
                    forceRefresh: configuration.retryToken > 0
                )
                await MainActor.run {
                    guard self.currentGeneration == generation else { return }
                    self.previewImageView.image = preview.image
                    self.croppedSourcePixelSize = preview.sourcePixelSize.applyingCrop(configuration.normalizedCropRect)
                    self.loadingIndicator.stopAnimating()
                    self.onFailureChanged?(nil)
                    self.onSourceSizeResolved?(preview.sourcePixelSize)
                    self.layoutContentIfPossible()
                    self.publishViewportState()
                    self.updateVisibleTiles()
                }
            } catch {
                await MainActor.run {
                    guard self.currentGeneration == generation else { return }
                    self.loadingIndicator.stopAnimating()
                    self.onFailureChanged?("Tap retry to request the page again.")
                }
            }
        }
    }

    private func configureZoom() {
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = configuration?.allowsZoom == true ? 4 : 1
        if scrollView.zoomScale < scrollView.minimumZoomScale || scrollView.zoomScale > scrollView.maximumZoomScale {
            scrollView.zoomScale = scrollView.minimumZoomScale
        }
    }

    private func layoutContentIfPossible() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        guard let previewImage = previewImageView.image else { return }

        let fitted = previewImage.size.aspectFit(in: bounds.size)
        let contentSize = CGSize(width: max(fitted.width, 1), height: max(fitted.height, 1))

        contentView.frame = CGRect(origin: .zero, size: contentSize)
        previewImageView.frame = contentView.bounds
        tileOverlayView.frame = contentView.bounds
        scrollView.contentSize = contentSize
        centerContentIfNeeded()
        updateVisibleTiles()
    }

    private func centerContentIfNeeded() {
        let horizontalInset = max((bounds.width - scrollView.contentSize.width) / 2, 0)
        let verticalInset = max((bounds.height - scrollView.contentSize.height) / 2, 0)
        scrollView.contentInset = UIEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)
    }

    private func visibleContentRect() -> CGRect {
        scrollView.convert(scrollView.bounds, to: contentView)
    }

    private func updateVisibleTiles() {
        guard configuration?.allowsZoom == true else {
            removeAllTiles()
            publishViewportState()
            return
        }
        guard scrollView.zoomScale > 1.01 else {
            removeAllTiles()
            publishViewportState()
            return
        }
        guard contentView.bounds.width > 0, contentView.bounds.height > 0 else { return }
        guard let configuration else { return }

        let scale = UIScreen.main.scale * scrollView.zoomScale
        let expandedVisibleRect = visibleContentRect().insetBy(dx: -160, dy: -160)
        let tileLength: CGFloat = 256
        let minColumn = max(Int(floor(expandedVisibleRect.minX / tileLength)), 0)
        let maxColumn = max(Int(floor(expandedVisibleRect.maxX / tileLength)), minColumn)
        let minRow = max(Int(floor(expandedVisibleRect.minY / tileLength)), 0)
        let maxRow = max(Int(floor(expandedVisibleRect.maxY / tileLength)), minRow)

        var neededKeys = Set<ReaderTileCacheKey>()

        for row in minRow...maxRow {
            for column in minColumn...maxColumn {
                let tileRect = CGRect(
                    x: CGFloat(column) * tileLength,
                    y: CGFloat(row) * tileLength,
                    width: tileLength,
                    height: tileLength
                ).intersection(contentView.bounds)
                guard !tileRect.isNull, tileRect.width > 0, tileRect.height > 0 else { continue }

                let normalizedTileRect = CGRect(
                    x: tileRect.minX / contentView.bounds.width,
                    y: tileRect.minY / contentView.bounds.height,
                    width: tileRect.width / contentView.bounds.width,
                    height: tileRect.height / contentView.bounds.height
                )
                let absoluteCropRect = configuration.normalizedCropRect.subrect(normalizedTileRect)
                let request = ReaderTileRequest(
                    source: configuration.source,
                    normalizedCropRect: absoluteCropRect,
                    targetPixelSize: CGSize(width: tileRect.width * scale, height: tileRect.height * scale),
                    colorTransform: configuration.colorTransform
                )
                let key = request.cacheKey
                neededKeys.insert(key)

                let imageView = tileViews[key] ?? {
                    let view = UIImageView(frame: tileRect)
                    view.backgroundColor = .clear
                    view.clipsToBounds = true
                    view.contentMode = .scaleToFill
                    tileOverlayView.addSubview(view)
                    tileViews[key] = view
                    return view
                }()
                imageView.frame = tileRect

                guard tileTasks[key] == nil, imageView.image == nil else { continue }

                let generation = currentGeneration
                let task = Task { [weak self] in
                    guard let self else { return }
                    do {
                        let tileImage = try await ReaderImagePipeline.shared.tileImage(
                            for: request,
                            variantKey: configuration.variantKey,
                            forceRefresh: configuration.retryToken > 0
                        )
                        await MainActor.run {
                            guard self.currentGeneration == generation else { return }
                            self.tileViews[key]?.image = tileImage
                            self.tileTasks[key] = nil
                        }
                    } catch {
                        await MainActor.run {
                            self.tileTasks[key] = nil
                        }
                    }
                }
                tileTasks[key] = task
            }
        }

        let staleKeys = Set(tileViews.keys).subtracting(neededKeys)
        for key in staleKeys {
            tileTasks[key]?.cancel()
            tileTasks[key] = nil
            tileViews[key]?.removeFromSuperview()
            tileViews[key] = nil
        }
    }

    private func removeAllTiles() {
        tileTasks.values.forEach { $0.cancel() }
        tileTasks.removeAll()
        tileViews.values.forEach { $0.removeFromSuperview() }
        tileViews.removeAll()
    }

    private func armEdgeTurnIfNeeded() {
        guard scrollView.zoomScale > 1.01 else { return }
        let contentWidth = scrollView.contentSize.width
        let leftBoundary = -scrollView.adjustedContentInset.left + 1
        let rightBoundary = contentWidth - scrollView.bounds.width + scrollView.adjustedContentInset.right - 1
        if scrollView.contentOffset.x <= leftBoundary {
            didArmRightPageTurn = true
        }
        if scrollView.contentOffset.x >= rightBoundary {
            didArmLeftPageTurn = true
        }
    }

    private func publishViewportState() {
        let contentWidth = scrollView.contentSize.width
        let leftBoundary = -scrollView.adjustedContentInset.left + 1
        let rightBoundary = contentWidth - scrollView.bounds.width + scrollView.adjustedContentInset.right - 1
        let atLeftEdge = scrollView.contentOffset.x <= leftBoundary
        let atRightEdge = scrollView.contentOffset.x >= rightBoundary

        if !atLeftEdge {
            didArmRightPageTurn = false
        }
        if !atRightEdge {
            didArmLeftPageTurn = false
        }

        onViewportStateChanged?(
            ReaderPageViewportState(
                scale: scrollView.zoomScale,
                contentOffset: scrollView.contentOffset,
                isLeftEdgeReadyForPageTurn: scrollView.zoomScale > 1.01 && didArmRightPageTurn,
                isRightEdgeReadyForPageTurn: scrollView.zoomScale > 1.01 && didArmLeftPageTurn
            )
        )
    }
}

private extension CGSize {
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

private extension CGRect {
    func subrect(_ child: CGRect) -> CGRect {
        CGRect(
            x: origin.x + size.width * child.origin.x,
            y: origin.y + size.height * child.origin.y,
            width: size.width * child.size.width,
            height: size.height * child.size.height
        )
    }
}
