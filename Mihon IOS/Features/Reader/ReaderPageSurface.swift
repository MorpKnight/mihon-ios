//
//  ReaderPageSurface.swift
//  Mihon IOS
//

import SwiftUI
import UIKit

struct ReaderPageSurface: View {
    @EnvironmentObject private var model: AppModel
    let imagePipeline: ReaderImagePipelining
    let item: ReaderRenderItem
    let filter: ReaderColorFilter
    let fillViewport: Bool
    let allowsImagePan: Bool
    let allowsHighDetailAtRest: Bool
    let onLongPress: (() -> Void)?
    let onImageMetadataResolved: (CGSize) -> Void
    let onLuminanceResolved: (CGFloat) -> Void
    let onInteractionStateChanged: (ReaderInteractionState) -> Void
    @State private var resolvedSourcePixelSize: CGSize = .zero
    @State private var loadFailureMessage: String?
    @State private var retryToken = 0

    var body: some View {
        ZStack {
            Color.black

            content
        }
        .frame(maxWidth: .infinity, maxHeight: fillViewport ? .infinity : nil)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.32)
                .onEnded { _ in
                    onLongPress?()
                }
        )
        .onAppear {
            onInteractionStateChanged(.default)
        }
        .onDisappear {
            onInteractionStateChanged(.default)
        }
    }

    @ViewBuilder
    private var content: some View {
        if item.page.assetKind == .image {
            imageContent
        } else {
            ScrollView {
                Text(item.page.body)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .grayscale(filter.enabled ? filter.grayscale : 0)
            .brightness(filter.enabled ? -filter.dimming * 0.4 : 0)
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        if let imageSource {
            ZStack {
                ReaderTiledPageSurface(
                    imagePipeline: imagePipeline,
                    source: imageSource,
                    variantKey: item.id,
                    normalizedCropRect: normalizedCropRect,
                    colorTransform: ReaderColorTransform(filter: filter),
                    allowsZoom: allowsImagePan,
                    allowsDetailTiles: allowsImagePan || allowsHighDetailAtRest,
                    sizingMode: fillViewport ? .fitWidth : .aspectFit,
                    retryToken: retryToken,
                    onSourceSizeResolved: { size in
                        resolvedSourcePixelSize = size
                        loadFailureMessage = nil
                        onImageMetadataResolved(size)
                    },
                    onPreviewLuminanceResolved: { luminance in
                        onLuminanceResolved(luminance)
                    },
                    onViewportStateChanged: { viewportState in
                        var readyDirections: Set<ReaderPanEdgeState> = []
                        if viewportState.isLeftEdgeReadyForPageTurn {
                            readyDirections.insert(.rightDrag)
                        }
                        if viewportState.isRightEdgeReadyForPageTurn {
                            readyDirections.insert(.leftDrag)
                        }
                        onInteractionStateChanged(
                            ReaderInteractionState(
                                scale: viewportState.scale,
                                offset: CGSize(width: viewportState.contentOffset.x, height: viewportState.contentOffset.y),
                                edgeDirection: nil,
                                readyDirections: readyDirections
                            )
                        )
                    },
                    onFailureChanged: { message in
                        loadFailureMessage = message
                        if message != nil {
                            onInteractionStateChanged(.default)
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: fillViewport ? .infinity : nil)
                .aspectRatio(fillViewport ? nil : (resolvedDisplayAspectRatio ?? 0.72), contentMode: .fit)

                if let failureMessage = loadFailureMessage {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.82))
                        Text("Image Failed")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(failureMessage)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        Button("Retry") {
                            retryToken += 1
                            loadFailureMessage = nil
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.18))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 24)
                }
            }
        } else {
            ReaderInlineFailureView(
                title: "Image Failed",
                message: "The page image source could not be resolved."
            )
        }
    }

    private var imageSource: ReaderImageAssetSource? {
        let localFileURL = model.fileURL(for: item.page)
        let remoteURL = item.page.remoteURL.flatMap(URL.init(string:))
        guard localFileURL != nil || remoteURL != nil else { return nil }
        let sourceIdentity = localFileURL?.path ?? remoteURL?.absoluteString ?? item.page.id
        return ReaderImageAssetSource(
            cacheKey: "\(item.page.id)|\(sourceIdentity)",
            remoteURL: remoteURL,
            localFileURL: localFileURL
        )
    }

    private var normalizedCropRect: CGRect {
        switch item.fragment {
        case .full:
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        case .spreadHalf(let side):
            return side.unitRect
        case .webtoonSlice(_, _, let unitRect):
            return unitRect
        }
    }

    private var resolvedDisplayAspectRatio: CGFloat? {
        guard resolvedSourcePixelSize.width > 0, resolvedSourcePixelSize.height > 0 else { return nil }
        let displayWidth = resolvedSourcePixelSize.width * normalizedCropRect.width
        let displayHeight = resolvedSourcePixelSize.height * normalizedCropRect.height
        guard displayWidth > 0, displayHeight > 0 else { return nil }
        return displayWidth / displayHeight
    }
}

struct ReaderRemoteImageView<Content: View>: View {
    @EnvironmentObject private var model: AppModel
    var imagePipeline: ReaderImagePipelining = ReaderImagePipeline.shared
    let url: URL
    let page: ReaderPage
    let aggressiveRetry: Bool
    let onImageMetadataResolved: (CGSize) -> Void
    @ViewBuilder let content: (UIImage) -> Content

    @State private var phase: RemoteImagePhase = .loading
    @State private var retryToken = 0

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            case .success(let image):
                content(image)
            case .failure(let message):
                VStack(spacing: 14) {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.85))
                        Text("Image Failed")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .allowsHitTesting(false)

                    Button("Retry") {
                        retryToken += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.18))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: retryToken) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        phase = .loading
        do {
            let image = try await imagePipeline.image(for: url, forceRefresh: retryToken > 0)
            onImageMetadataResolved(image.size)
            phase = .success(image)
        } catch {
            model.appendDiagnostic(
                kind: .reader,
                title: "Reader Remote Image Failed",
                message: error.localizedDescription,
                metadata: [
                    "pageID": page.id,
                    "url": url.absoluteString
                ]
            )
            if aggressiveRetry, retryToken == 0 {
                do {
                    let image = try await imagePipeline.image(for: url, forceRefresh: true)
                    onImageMetadataResolved(image.size)
                    phase = .success(image)
                    return
                } catch { }
            }
            phase = .failure("Tap retry to request the page again.")
        }
    }
}

enum RemoteImagePhase {
    case loading
    case success(UIImage)
    case failure(String)
}

struct CachedLocalImageView<Content: View>: View {
    @EnvironmentObject private var model: AppModel
    let page: ReaderPage
    let onImageMetadataResolved: (CGSize) -> Void
    @ViewBuilder let content: (UIImage) -> Content

    @State private var phase: LocalImagePhase = .loading

    var body: some View {
        Group {
            switch phase {
            case .loading:
                Rectangle()
                    .fill(.clear)
                    .task(id: page.id) {
                        await loadFromDisk()
                    }
            case .success(let uiImage):
                content(uiImage)
            case .failure(let message):
                ReaderInlineFailureView(title: "Downloaded Page Failed", message: message)
            }
        }
    }

    @MainActor
    private func loadFromDisk() async {
        guard let fileURL = model.fileURL(for: page) else {
            phase = .failure("The downloaded file could not be found.")
            model.appendDiagnostic(
                kind: .reader,
                title: "Reader Local Asset Missing",
                message: "A downloaded page file could not be resolved.",
                metadata: [
                    "pageID": page.id,
                    "assetPath": page.assetPath ?? "<nil>",
                    "remoteURL": page.remoteURL ?? "<nil>"
                ]
            )
            return
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            phase = .failure("The downloaded file is missing from storage.")
            model.appendDiagnostic(
                kind: .reader,
                title: "Reader Local Asset Missing",
                message: "A downloaded page path resolved, but the file is absent on disk.",
                metadata: [
                    "pageID": page.id,
                    "assetPath": fileURL.path
                ]
            )
            return
        }

        guard
            let data = try? Data(contentsOf: fileURL),
            let image = UIImage(data: data)
        else {
            phase = .failure("The downloaded file could not be decoded.")
            model.appendDiagnostic(
                kind: .reader,
                title: "Reader Local Decode Failed",
                message: "A downloaded page file exists but could not be decoded into an image.",
                metadata: [
                    "pageID": page.id,
                    "assetPath": fileURL.path
                ]
            )
            return
        }

        onImageMetadataResolved(image.size)
        phase = .success(image)
    }
}

enum LocalImagePhase {
    case loading
    case success(UIImage)
    case failure(String)
}

struct ReaderInlineFailureView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.82))
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum ReaderPanEdgeState: Hashable {
    case leftDrag
    case rightDrag
}

struct ReaderInteractionState: Equatable {
    static let resistanceThreshold: CGFloat = 72
    static let `default` = ReaderInteractionState(scale: 1, offset: .zero, edgeDirection: nil, readyDirections: [])

    let scale: CGFloat
    let offset: CGSize
    let edgeDirection: ReaderPanEdgeState?
    let readyDirections: Set<ReaderPanEdgeState>

    var consumesTapNavigation: Bool {
        scale > 1.01
    }
}

struct ReaderPanResolution {
    let clampedOffset: CGSize
    let edgeDirection: ReaderPanEdgeState?
    let overscrollDistance: CGFloat
}
