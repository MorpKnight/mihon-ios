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

    func setAggressiveRetryEnabled(_ enabled: Bool) async

    func retryTelemetrySnapshot() async -> ReaderImagePipelineTelemetry

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
    private var inFlightIntents: [URL: ReaderImageRequestIntent] = [:]
    private var prefetchTasksByURL: [URL: Task<Void, Never>] = [:]
    private var activeWindowChapterID: String?
    private var activeWindowURLs: Set<URL> = []
    private var aggressiveRetryEnabled = false
    private var telemetry = ReaderImagePipelineTelemetry()
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
        try await image(for: url, forceRefresh: forceRefresh, intent: .visible)
    }

    func setAggressiveRetryEnabled(_ enabled: Bool) async {
        aggressiveRetryEnabled = enabled
    }

    func retryTelemetrySnapshot() async -> ReaderImagePipelineTelemetry {
        telemetry
    }

    private func image(for url: URL, forceRefresh: Bool, intent: ReaderImageRequestIntent) async throws -> UIImage {
        telemetryRecordRequest(intent: intent)
        if let existingTask = inFlight[url] {
            let existingIntent = inFlightIntents[url] ?? .visible
            let shouldSupersede = forceRefresh || intent.supersedes(existingIntent)
            if shouldSupersede {
                existingTask.cancel()
                inFlight[url] = nil
                inFlightIntents[url] = nil
                telemetryRecordCancellation()
            } else {
                return try await existingTask.value
            }
        }

        let retryPolicy = retryPolicy(for: intent)
        let task = Task<UIImage, Error>(priority: intent.taskPriority) {
            var request = URLRequest(url: url)
            request.cachePolicy = forceRefresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
            request.timeoutInterval = 20
            return try await cache.image(
                for: url,
                key: "reader-image|\(url.absoluteString)",
                policy: forceRefresh ? .reloadIgnoringCache : .returnCacheElseLoad,
                intent: .readerFullQuality
            ) {
                try await self.fetchRemoteImageData(request: request, retryPolicy: retryPolicy, intent: intent)
            }
        }

        inFlight[url] = task
        inFlightIntents[url] = intent

        do {
            let image = try await task.value
            inFlight[url] = nil
            inFlightIntents[url] = nil
            return image
        } catch {
            if error is CancellationError {
                telemetryRecordCancellation()
            } else {
                telemetryRecordFailure(reason: classifyErrorReason(error))
            }
            inFlight[url] = nil
            inFlightIntents[url] = nil
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
            inFlightIntents[url] = nil
        }

        for url in targetURLs {
            if Task.isCancelled { return }
            if inFlight[url] != nil || prefetchTasksByURL[url] != nil { continue }
            let task = Task<Void, Never> {
                defer {
                    Task { await self.finishPrefetch(for: url) }
                }
                guard !Task.isCancelled else { return }
                _ = try? await image(for: url, forceRefresh: false, intent: .prefetch)
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
        inFlightIntents.removeAll()
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
        return try await fetchRemoteImageData(request: request, retryPolicy: retryPolicy(for: .visible), intent: .visible)
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

    private func fetchRemoteImageData(
        request: URLRequest,
        retryPolicy: ReaderImageRetryPolicy,
        intent: ReaderImageRequestIntent
    ) async throws -> Data {
        var attempt = 0
        while true {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                    throw URLError(.badServerResponse)
                }
                return data
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard retryPolicy.canRetry(error: error), attempt < retryPolicy.delays.count else {
                    throw error
                }
                let delay = retryPolicy.delays[attempt]
                attempt += 1
                telemetryRecordRetry(reason: classifyErrorReason(error))
                try await Task.sleep(nanoseconds: delay)
            }
        }
    }

    private func telemetryRecordRequest(intent: ReaderImageRequestIntent) {
        telemetry.totalRequests += 1
        if intent == .prefetch {
            telemetry.prefetchRequests += 1
        } else {
            telemetry.visibleRequests += 1
        }
    }

    private func telemetryRecordRetry(reason: String) {
        telemetry.retries += 1
        telemetry.retryReasons[reason, default: 0] += 1
    }

    private func telemetryRecordFailure(reason: String) {
        telemetry.failures += 1
        telemetry.failureReasons[reason, default: 0] += 1
    }

    private func telemetryRecordCancellation() {
        telemetry.cancellations += 1
    }

    private func classifyErrorReason(_ error: Error) -> String {
        if error is CancellationError {
            return "cancelled"
        }
        if let urlError = error as? URLError {
            return "url:\(urlError.code.rawValue)"
        }
        return "other"
    }

    private func retryPolicy(for intent: ReaderImageRequestIntent) -> ReaderImageRetryPolicy {
        let baseDelaysMS: [UInt64]
        if aggressiveRetryEnabled {
            baseDelaysMS = [80, 180, 350, 700]
        } else {
            baseDelaysMS = [150, 400, 900]
        }

        let delays: [UInt64]
        switch intent {
        case .prefetch:
            delays = Array(baseDelaysMS.prefix(max(baseDelaysMS.count - 1, 1)))
        case .visible:
            delays = baseDelaysMS
        }

        return ReaderImageRetryPolicy(delays: delays.map { $0 * 1_000_000 })
    }
}

struct ReaderImagePipelineTelemetry: Sendable {
    var totalRequests = 0
    var visibleRequests = 0
    var prefetchRequests = 0
    var retries = 0
    var failures = 0
    var cancellations = 0
    var retryReasons: [String: Int] = [:]
    var failureReasons: [String: Int] = [:]
}

private enum ReaderImageRequestIntent {
    case visible
    case prefetch

    var taskPriority: TaskPriority {
        switch self {
        case .visible:
            return .userInitiated
        case .prefetch:
            return .utility
        }
    }

    func supersedes(_ other: ReaderImageRequestIntent) -> Bool {
        switch (self, other) {
        case (.visible, .prefetch):
            return true
        default:
            return false
        }
    }
}

private struct ReaderImageRetryPolicy {
    let delays: [UInt64]

    func canRetry(error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .badServerResponse:
            return true
        default:
            return false
        }
    }
}
