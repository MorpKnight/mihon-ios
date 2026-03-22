//
//  ReaderImagePipeline.swift
//  Mihon IOS
//

import CoreImage
import UIKit

protocol ReaderImagePipelining: Sendable {
    func previewImage(
        for source: ReaderImageAssetSource,
        variantKey: String,
        normalizedCropRect: CGRect,
        maxPixelSize: CGFloat,
        colorTransform: ReaderColorTransform,
        forceRefresh: Bool
    ) async throws -> ReaderPreviewImageResult

    func tileImage(
        for request: ReaderTileRequest,
        variantKey: String,
        forceRefresh: Bool
    ) async throws -> UIImage

    func image(for url: URL, forceRefresh: Bool) async throws -> UIImage

    func updateActiveWindow(
        chapterID: String,
        logicalPages: [ReaderLogicalPage],
        currentIndex: Int,
        lookahead: Int
    ) async

    func cancelWindow(for chapterID: String?)
}

actor ReaderImagePipeline: ReaderImagePipelining {
    static let shared = ReaderImagePipeline()

    private let cache: AppCacheManaging = AppCacheController.shared
    private var inFlight: [URL: Task<UIImage, Error>] = [:]
    private var prefetchTasksByURL: [URL: Task<Void, Never>] = [:]
    private var activeWindowChapterID: String?
    private var activeWindowURLs: Set<URL> = []
    private let ciContext = CIContext(options: nil)

    func previewImage(
        for source: ReaderImageAssetSource,
        variantKey _: String,
        normalizedCropRect: CGRect,
        maxPixelSize: CGFloat,
        colorTransform: ReaderColorTransform,
        forceRefresh: Bool
    ) async throws -> ReaderPreviewImageResult {
        let dimensions = try await cache.readerImageDimensions(
            for: source.cacheKey,
            policy: forceRefresh ? .reloadIgnoringCache : .returnCacheElseLoad
        ) {
            try await self.loadData(for: source, forceRefresh: forceRefresh)
        }
        let previewImage = try await cache.readerPreviewImage(
            for: source.cacheKey,
            policy: forceRefresh ? .reloadIgnoringCache : .returnCacheElseLoad,
            normalizedCropRect: normalizedCropRect,
            maxPixelSize: maxPixelSize
        ) {
            try await self.loadData(for: source, forceRefresh: forceRefresh)
        }
        let transformed = applyColorTransform(colorTransform, to: previewImage) ?? previewImage
        return ReaderPreviewImageResult(image: transformed, sourcePixelSize: dimensions)
    }

    func tileImage(
        for request: ReaderTileRequest,
        variantKey _: String,
        forceRefresh: Bool
    ) async throws -> UIImage {
        let tileImage = try await cache.readerTileImage(
            for: request.source.cacheKey,
            policy: forceRefresh ? .reloadIgnoringCache : .returnCacheElseLoad,
            normalizedCropRect: request.normalizedCropRect,
            targetPixelSize: request.targetPixelSize
        ) {
            try await self.loadData(for: request.source, forceRefresh: forceRefresh)
        }
        return applyColorTransform(request.colorTransform, to: tileImage) ?? tileImage
    }

    func image(for url: URL, forceRefresh: Bool) async throws -> UIImage {
        if !forceRefresh, let task = inFlight[url] {
            return try await task.value
        }

        let task = Task<UIImage, Error> {
            var request = URLRequest(url: url)
            request.cachePolicy = forceRefresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
            request.timeoutInterval = 20
            return try await cache.image(
                for: url,
                key: "reader-image|\(url.absoluteString)",
                policy: forceRefresh ? .reloadIgnoringCache : .returnCacheElseLoad,
                intent: .readerFullQuality
            ) {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                    throw URLError(.badServerResponse)
                }
                return data
            }
        }

        inFlight[url] = task

        do {
            let image = try await task.value
            inFlight[url] = nil
            return image
        } catch {
            inFlight[url] = nil
            throw error
        }
    }

    func updateActiveWindow(
        chapterID: String,
        logicalPages: [ReaderLogicalPage],
        currentIndex: Int,
        lookahead: Int
    ) async {
        let boundedLookahead = max(lookahead, 0)
        let targetURLs = Set(logicalPages.enumerated().compactMap { index, logicalPage -> URL? in
            guard abs(index - currentIndex) <= boundedLookahead else { return nil }
            guard let remoteURL = logicalPage.sourcePage.remoteURL else { return nil }
            return URL(string: remoteURL)
        })

        if activeWindowChapterID != chapterID {
            cancelPrefetchTasks()
            activeWindowURLs.removeAll()
            activeWindowChapterID = chapterID
        }

        let staleURLs = activeWindowURLs.subtracting(targetURLs)
        for (url, task) in prefetchTasksByURL where !targetURLs.contains(url) {
            task.cancel()
            prefetchTasksByURL[url] = nil
        }
        for url in staleURLs {
            inFlight[url]?.cancel()
            inFlight[url] = nil
        }

        for url in targetURLs {
            if Task.isCancelled { return }
            if inFlight[url] != nil || prefetchTasksByURL[url] != nil { continue }
            let task = Task<Void, Never> {
                defer {
                    Task { await self.finishPrefetch(for: url) }
                }
                guard !Task.isCancelled else { return }
                _ = try? await image(for: url, forceRefresh: false)
            }
            prefetchTasksByURL[url] = task
        }

        if !staleURLs.isEmpty {
            await cache.trimMemory(fraction: 0.15)
        }
        activeWindowURLs = targetURLs
    }

    func clear() async {
        cancelPrefetchTasks()
        for (_, task) in inFlight {
            task.cancel()
        }
        inFlight.removeAll()
        activeWindowChapterID = nil
        activeWindowURLs.removeAll()
        await cache.clear(.image)
    }

    func cancelWindow(for chapterID: String? = nil) {
        guard chapterID == nil || chapterID == activeWindowChapterID else { return }
        cancelPrefetchTasks()
        activeWindowChapterID = nil
        activeWindowURLs.removeAll()
    }

    private func loadData(for source: ReaderImageAssetSource, forceRefresh: Bool) async throws -> Data {
        if let localFileURL = source.localFileURL {
            return try await Task.detached(priority: .utility) {
                try Data(contentsOf: localFileURL, options: [.mappedIfSafe])
            }.value
        }

        guard let remoteURL = source.remoteURL else {
            throw URLError(.fileDoesNotExist)
        }

        var request = URLRequest(url: remoteURL)
        request.cachePolicy = forceRefresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func applyColorTransform(_ transform: ReaderColorTransform, to image: UIImage) -> UIImage? {
        guard transform.enabled, let cgImage = image.cgImage else { return image }
        let input = CIImage(cgImage: cgImage)

        let controls = CIFilter(name: "CIColorControls")
        controls?.setValue(input, forKey: kCIInputImageKey)
        controls?.setValue(1 - transform.grayscale, forKey: kCIInputSaturationKey)
        controls?.setValue(-transform.dimming * 0.4, forKey: kCIInputBrightnessKey)

        guard
            let output = controls?.outputImage,
            let rendered = ciContext.createCGImage(output, from: output.extent)
        else {
            return image
        }
        return UIImage(cgImage: rendered)
    }

    private func cancelPrefetchTasks() {
        for task in prefetchTasksByURL.values {
            task.cancel()
        }
        prefetchTasksByURL.removeAll()
    }

    private func finishPrefetch(for url: URL) {
        prefetchTasksByURL[url] = nil
    }
}
