//
//  AppCacheController.swift
//  Mihon IOS
//

import CryptoKit
import Foundation
import ImageIO
import UIKit

enum CacheDomain: String, CaseIterable, Codable, Hashable, Identifiable {
    case image
    case sourceMetadata
    case networkResponse
    case all

    var id: String { rawValue }
}

enum CachePolicy: String, Codable, Hashable {
    case memoryOnly
    case memoryAndDisk
    case returnCacheElseLoad
    case reloadIgnoringCache
}

enum ImageDecodeIntent: String, Codable, Hashable {
    case thumbnail
    case readerPreview
    case readerFullQuality
}

struct CacheEntryMetadata: Codable, Hashable {
    let key: String
    let domain: CacheDomain
    let expirationDate: Date?
    let byteCount: Int
    let createdAt: Date
}

struct CacheStats: Hashable {
    let memoryImageCount: Int
    let memoryDataCount: Int
    let diskImageBytes: Int
    let diskMetadataBytes: Int
    let diskNetworkBytes: Int
    let hitCount: Int
    let missCount: Int
}

protocol AppCacheManaging {
    func image(for url: URL, key: String, policy: CachePolicy, intent: ImageDecodeIntent, loader: @escaping @Sendable () async throws -> Data) async throws -> UIImage
    func readerImageData(for key: String, policy: CachePolicy, loader: @escaping @Sendable () async throws -> Data) async throws -> Data
    func readerPreviewImage(for key: String, policy: CachePolicy, normalizedCropRect: CGRect, maxPixelSize: CGFloat, loader: @escaping @Sendable () async throws -> Data) async throws -> UIImage
    func readerTileImage(for key: String, policy: CachePolicy, normalizedCropRect: CGRect, targetPixelSize: CGSize, loader: @escaping @Sendable () async throws -> Data) async throws -> UIImage
    func readerImageDimensions(for key: String, policy: CachePolicy, loader: @escaping @Sendable () async throws -> Data) async throws -> CGSize
    func data(for key: String, domain: CacheDomain, policy: CachePolicy, ttl: TimeInterval?, loader: @escaping @Sendable () async throws -> Data) async throws -> Data
    func value<T: Codable>(for key: String, domain: CacheDomain, policy: CachePolicy, ttl: TimeInterval?, loader: @escaping @Sendable () async throws -> T) async throws -> T
    func clear(_ domain: CacheDomain) async
    func stats() async -> CacheStats
    func reconfigure(_ config: CacheConfiguration) async
    func trimMemory(fraction: Double) async
}

private struct DiskCacheEnvelope: Codable {
    let metadata: CacheEntryMetadata
    let payload: Data
}

actor AppCacheController: AppCacheManaging {
    static let shared = AppCacheController()

    private let fileManager: FileManager
    private let baseDirectory: URL
    private let memoryImageCache: LRUMemoryCache<String, UIImage>
    private let memoryDataCache: LRUMemoryCache<String, NSData>
    private var inFlightData: [String: Task<Data, Error>] = [:]
    private var dataMemoryKeysByDomain: [CacheDomain: Set<String>] = [:]
    private var hitCount = 0
    private var missCount = 0
    private var config: CacheConfiguration

    init(fileManager: FileManager = .default, configuration: CacheConfiguration = .default) {
        self.fileManager = fileManager
        self.config = configuration
        let root = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        self.baseDirectory = root.appendingPathComponent("MihonCache", isDirectory: true)
        self.memoryImageCache = LRUMemoryCache(
            countLimit: configuration.imageCountLimit,
            totalCostLimit: configuration.imageBytesLimit
        )
        self.memoryDataCache = LRUMemoryCache(
            countLimit: configuration.dataCountLimit,
            totalCostLimit: configuration.dataBytesLimit
        )
        createDirectoriesIfNeeded()
    }

    func reconfigure(_ newConfig: CacheConfiguration) {
        config = newConfig
        memoryImageCache.countLimit = newConfig.imageCountLimit
        memoryImageCache.totalCostLimit = newConfig.imageBytesLimit
        memoryDataCache.countLimit = newConfig.dataCountLimit
        memoryDataCache.totalCostLimit = newConfig.dataBytesLimit
    }

    func trimMemory(fraction: Double) {
        memoryImageCache.trimToFraction(fraction)
        memoryDataCache.trimToFraction(fraction)
    }

    func image(for url: URL, key: String, policy: CachePolicy, intent: ImageDecodeIntent, loader: @escaping @Sendable () async throws -> Data) async throws -> UIImage {
        let imageCacheKey = "\(key)|intent=\(intent.rawValue)"
        if policy != .reloadIgnoringCache, let cached = memoryImageCache.object(forKey: imageCacheKey) {
            hitCount += 1
            return cached
        }

        let imageData = try await data(for: key, domain: .image, policy: policy, ttl: 60 * 60 * 24 * 7, loader: loader)
        guard let image = Self.decodedImage(data: imageData, for: url, intent: intent) else {
            throw URLError(.cannotDecodeContentData)
        }

        memoryImageCache.setObject(image, forKey: imageCacheKey, cost: imageData.count)
        return image
    }

    func readerImageData(for key: String, policy: CachePolicy, loader: @escaping @Sendable () async throws -> Data) async throws -> Data {
        let cacheKey = namespacedKey(key, domain: .image)

        if policy != .reloadIgnoringCache, let diskValue = try? loadDiskEntry(for: cacheKey, domain: .image) {
            if !isExpired(diskValue.metadata.expirationDate) {
                hitCount += 1
                return diskValue.payload
            }
            try? removeDiskEntry(for: cacheKey, domain: .image)
        }

        if let task = inFlightData[cacheKey] {
            hitCount += 1
            return try await task.value
        }

        missCount += 1
        let task = Task<Data, Error> {
            try await loader()
        }
        inFlightData[cacheKey] = task

        do {
            let payload = try await task.value
            if policy != .memoryOnly {
                try storeDiskEntry(payload: payload, for: cacheKey, domain: .image, ttl: 60 * 60 * 24 * 7)
                try trimDiskIfNeeded(for: .image)
            }
            inFlightData[cacheKey] = nil
            return payload
        } catch {
            inFlightData[cacheKey] = nil
            throw error
        }
    }

    func readerPreviewImage(
        for key: String,
        policy: CachePolicy,
        normalizedCropRect: CGRect,
        maxPixelSize: CGFloat,
        loader: @escaping @Sendable () async throws -> Data
    ) async throws -> UIImage {
        let imageCacheKey = "\(key)|reader-preview|\(Self.rectKey(normalizedCropRect))|\(Int(maxPixelSize.rounded()))"
        if policy != .reloadIgnoringCache, let cached = memoryImageCache.object(forKey: imageCacheKey) {
            hitCount += 1
            return cached
        }

        let imageData = try await readerImageData(for: key, policy: policy, loader: loader)
        guard let image = Self.croppedDownsampledImage(data: imageData, normalizedCropRect: normalizedCropRect, targetPixelSize: CGSize(width: maxPixelSize, height: maxPixelSize)) else {
            throw URLError(.cannotDecodeContentData)
        }

        memoryImageCache.setObject(image, forKey: imageCacheKey, cost: Self.imageCost(for: image))
        return image
    }

    func readerTileImage(
        for key: String,
        policy: CachePolicy,
        normalizedCropRect: CGRect,
        targetPixelSize: CGSize,
        loader: @escaping @Sendable () async throws -> Data
    ) async throws -> UIImage {
        let imageCacheKey = "\(key)|reader-tile|\(Self.rectKey(normalizedCropRect))|\(Self.sizeKey(targetPixelSize))"
        if policy != .reloadIgnoringCache, let cached = memoryImageCache.object(forKey: imageCacheKey) {
            hitCount += 1
            return cached
        }

        let imageData = try await readerImageData(for: key, policy: policy, loader: loader)
        guard let image = Self.croppedDownsampledImage(data: imageData, normalizedCropRect: normalizedCropRect, targetPixelSize: targetPixelSize) else {
            throw URLError(.cannotDecodeContentData)
        }

        memoryImageCache.setObject(image, forKey: imageCacheKey, cost: Self.imageCost(for: image))
        return image
    }

    func readerImageDimensions(for key: String, policy: CachePolicy, loader: @escaping @Sendable () async throws -> Data) async throws -> CGSize {
        let imageData = try await readerImageData(for: key, policy: policy, loader: loader)
        guard let dimensions = Self.imageDimensions(data: imageData) else {
            throw URLError(.cannotDecodeContentData)
        }
        return dimensions
    }

    func data(for key: String, domain: CacheDomain, policy: CachePolicy, ttl: TimeInterval?, loader: @escaping @Sendable () async throws -> Data) async throws -> Data {
        let cacheKey = namespacedKey(key, domain: domain)

        if policy != .reloadIgnoringCache, let cached = memoryDataCache.object(forKey: cacheKey) {
            hitCount += 1
            return cached as Data
        }

        if policy != .memoryOnly, let diskValue = try? loadDiskEntry(for: cacheKey, domain: domain) {
            if !isExpired(diskValue.metadata.expirationDate) {
                hitCount += 1
                memoryDataCache.setObject(diskValue.payload as NSData, forKey: cacheKey, cost: diskValue.payload.count)
                trackDataMemoryKey(cacheKey, domain: domain)
                return diskValue.payload
            }
            try? removeDiskEntry(for: cacheKey, domain: domain)
        }

        if let task = inFlightData[cacheKey] {
            hitCount += 1
            return try await task.value
        }

        missCount += 1
        let task = Task<Data, Error> {
            try await loader()
        }
        inFlightData[cacheKey] = task

        do {
            let payload = try await task.value
            memoryDataCache.setObject(payload as NSData, forKey: cacheKey, cost: payload.count)
            trackDataMemoryKey(cacheKey, domain: domain)
            if policy != .memoryOnly {
                try storeDiskEntry(payload: payload, for: cacheKey, domain: domain, ttl: ttl)
                try trimDiskIfNeeded(for: domain)
            }
            inFlightData[cacheKey] = nil
            return payload
        } catch {
            inFlightData[cacheKey] = nil
            throw error
        }
    }

    func value<T: Codable>(for key: String, domain: CacheDomain, policy: CachePolicy, ttl: TimeInterval?, loader: @escaping @Sendable () async throws -> T) async throws -> T {
        let payload = try await data(for: key, domain: domain, policy: policy, ttl: ttl) {
            let value = try await loader()
            return try JSONEncoder().encode(value)
        }
        return try JSONDecoder().decode(T.self, from: payload)
    }

    func clear(_ domain: CacheDomain) async {
        if domain == .all || domain == .image {
            memoryImageCache.removeAllObjects()
        }
        if domain == .all {
            memoryDataCache.removeAllObjects()
            dataMemoryKeysByDomain.removeAll()
        } else if let keys = dataMemoryKeysByDomain[domain] {
            let liveKeys = memoryDataCache.allKeys()
            for key in keys.intersection(liveKeys) {
                memoryDataCache.removeObject(forKey: key)
            }
            dataMemoryKeysByDomain[domain] = nil
        }

        let domains = domain == .all ? [CacheDomain.image, .sourceMetadata, .networkResponse] : [domain]
        for target in domains where target != .all {
            try? fileManager.removeItem(at: directory(for: target))
            try? fileManager.createDirectory(at: directory(for: target), withIntermediateDirectories: true, attributes: nil)
        }
    }

    func stats() async -> CacheStats {
        CacheStats(
            memoryImageCount: memoryImageCache.count,
            memoryDataCount: memoryDataCache.count,
            diskImageBytes: diskUsage(for: .image),
            diskMetadataBytes: diskUsage(for: .sourceMetadata),
            diskNetworkBytes: diskUsage(for: .networkResponse),
            hitCount: hitCount,
            missCount: missCount
        )
    }

    private func createDirectoriesIfNeeded() {
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true, attributes: nil)
        for domain in [CacheDomain.image, .sourceMetadata, .networkResponse] {
            try? fileManager.createDirectory(at: directory(for: domain), withIntermediateDirectories: true, attributes: nil)
        }
    }

    private func namespacedKey(_ key: String, domain: CacheDomain) -> String {
        "\(domain.rawValue)::\(key)"
    }

    private func trackDataMemoryKey(_ key: String, domain: CacheDomain) {
        dataMemoryKeysByDomain[domain, default: []].insert(key)
    }

    private func directory(for domain: CacheDomain) -> URL {
        baseDirectory.appendingPathComponent(domain.rawValue, isDirectory: true)
    }

    private func fileURL(for key: String, domain: CacheDomain) -> URL {
        directory(for: domain).appendingPathComponent(Self.digest(key) + ".cache")
    }

    private func loadDiskEntry(for key: String, domain: CacheDomain) throws -> DiskCacheEnvelope? {
        let url = fileURL(for: key, domain: domain)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(DiskCacheEnvelope.self, from: data)
    }

    private func storeDiskEntry(payload: Data, for key: String, domain: CacheDomain, ttl: TimeInterval?) throws {
        let url = fileURL(for: key, domain: domain)
        let envelope = DiskCacheEnvelope(
            metadata: CacheEntryMetadata(
                key: key,
                domain: domain,
                expirationDate: ttl.map { Date().addingTimeInterval($0) },
                byteCount: payload.count,
                createdAt: .now
            ),
            payload: payload
        )
        let data = try JSONEncoder().encode(envelope)
        try data.write(to: url, options: .atomic)
    }

    private func removeDiskEntry(for key: String, domain: CacheDomain) throws {
        let url = fileURL(for: key, domain: domain)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func trimDiskIfNeeded(for domain: CacheDomain) throws {
        let maxBytes: Int
        switch domain {
        case .image:
            maxBytes = config.diskImageBytesLimit
        case .sourceMetadata:
            maxBytes = config.diskMetadataBytesLimit
        case .networkResponse:
            maxBytes = config.diskNetworkBytesLimit
        case .all:
            return
        }

        let dir = directory(for: domain)
        let files = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles])
        let items: [(URL, Date, Int)] = files.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { return nil }
            return (url, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0)
        }
        let total = items.reduce(0) { $0 + $1.2 }
        guard total > maxBytes else { return }

        var running = total
        for item in items.sorted(by: { $0.1 < $1.1 }) {
            try? fileManager.removeItem(at: item.0)
            running -= item.2
            if running <= maxBytes { break }
        }
    }

    private func diskUsage(for domain: CacheDomain) -> Int {
        let dir = directory(for: domain)
        let files = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])) ?? []
        return files.reduce(0) { partial, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return partial + size
        }
    }

    private func isExpired(_ expirationDate: Date?) -> Bool {
        guard let expirationDate else { return false }
        return expirationDate < .now
    }

    private static func digest(_ key: String) -> String {
        let data = Data(key.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private static func decodedImage(data: Data, for url: URL, intent: ImageDecodeIntent) -> UIImage? {
        switch intent {
        case .thumbnail:
            return downsampledImage(data: data, maxPixelSize: 1_200)
        case .readerPreview:
            return downsampledImage(data: data, maxPixelSize: 2_800)
        case .readerFullQuality:
            return fullQualityImage(data: data)
        }
    }

    private static func downsampledImage(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private static func fullQualityImage(data: Data) -> UIImage? {
        let options = [kCGImageSourceShouldCache: true] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return UIImage(data: data) }
        return UIImage(cgImage: cgImage)
    }

    private static func imageDimensions(data: Data) -> CGSize? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
            let height = properties[kCGImagePropertyPixelHeight] as? CGFloat
        else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    private static func croppedDownsampledImage(data: Data, normalizedCropRect: CGRect, targetPixelSize: CGSize) -> UIImage? {
        let normalizedRect = normalizedCropRect.standardized.clampedToUnitRect
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }

        let previewMaxPixel = max(
            targetPixelSize.width / max(normalizedRect.width, 0.01),
            targetPixelSize.height / max(normalizedRect.height, 0.01)
        )
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(previewMaxPixel, 1),
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary

        guard let downsampled = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        let cropRect = CGRect(
            x: normalizedRect.origin.x * CGFloat(downsampled.width),
            y: normalizedRect.origin.y * CGFloat(downsampled.height),
            width: normalizedRect.width * CGFloat(downsampled.width),
            height: normalizedRect.height * CGFloat(downsampled.height)
        ).integral
        guard cropRect.width > 0, cropRect.height > 0 else { return UIImage(cgImage: downsampled) }
        guard let cropped = downsampled.cropping(to: cropRect) else { return UIImage(cgImage: downsampled) }
        return UIImage(cgImage: cropped)
    }

    private static func rectKey(_ rect: CGRect) -> String {
        let values = [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height].map { Int(($0 * 10_000).rounded()) }
        return values.map(String.init).joined(separator: "x")
    }

    private static func sizeKey(_ size: CGSize) -> String {
        "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }

    private static func imageCost(for image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}

private extension CGRect {
    var clampedToUnitRect: CGRect {
        CGRect(
            x: min(max(origin.x, 0), 1),
            y: min(max(origin.y, 0), 1),
            width: min(max(size.width, 0), 1 - min(max(origin.x, 0), 1)),
            height: min(max(size.height, 0), 1 - min(max(origin.y, 0), 1))
        )
    }
}
