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

struct CacheEntryMetadata: Codable, Hashable {
    let key: String
    let domain: CacheDomain
    let expirationDate: Date?
    let byteCount: Int
    let createdAt: Date
    let lastAccessedAt: Date
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
    func image(for url: URL, key: String, policy: CachePolicy, loader: @escaping @Sendable () async throws -> Data) async throws -> UIImage
    func data(for key: String, domain: CacheDomain, policy: CachePolicy, ttl: TimeInterval?, loader: @escaping @Sendable () async throws -> Data) async throws -> Data
    func value<T: Codable>(for key: String, domain: CacheDomain, policy: CachePolicy, ttl: TimeInterval?, loader: @escaping @Sendable () async throws -> T) async throws -> T
    func clear(_ domain: CacheDomain) async
    func stats() async -> CacheStats
}

private struct DiskCacheEnvelope: Codable {
    let metadata: CacheEntryMetadata
    let payload: Data
}

actor AppCacheController: AppCacheManaging {
    static let shared = AppCacheController()

    private let fileManager: FileManager
    private let baseDirectory: URL
    private let memoryImageCache = NSCache<NSString, UIImage>()
    private let memoryDataCache = NSCache<NSString, NSData>()
    private var inFlightData: [String: Task<Data, Error>] = [:]
    private var imageMemoryKeys = Set<String>()
    private var dataMemoryKeys = Set<String>()
    private var dataMemoryKeysByDomain: [CacheDomain: Set<String>] = [:]
    private var hitCount = 0
    private var missCount = 0

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let root = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        self.baseDirectory = root.appendingPathComponent("MihonCache", isDirectory: true)
        memoryImageCache.countLimit = 120
        memoryImageCache.totalCostLimit = 96 * 1_024 * 1_024
        memoryDataCache.countLimit = 256
        memoryDataCache.totalCostLimit = 48 * 1_024 * 1_024
        createDirectoriesIfNeeded()
    }

    func image(for url: URL, key: String, policy: CachePolicy, loader: @escaping @Sendable () async throws -> Data) async throws -> UIImage {
        let cacheKey = key as NSString
        if policy != .reloadIgnoringCache, let cached = memoryImageCache.object(forKey: cacheKey) {
            hitCount += 1
            return cached
        }

        let imageData = try await data(for: key, domain: .image, policy: policy, ttl: 60 * 60 * 24 * 7, loader: loader)
        guard let image = Self.downsampledImage(data: imageData, for: url) ?? UIImage(data: imageData) else {
            throw URLError(.cannotDecodeContentData)
        }

        memoryImageCache.setObject(image, forKey: cacheKey, cost: imageData.count)
        imageMemoryKeys.insert(key)
        return image
    }

    func data(for key: String, domain: CacheDomain, policy: CachePolicy, ttl: TimeInterval?, loader: @escaping @Sendable () async throws -> Data) async throws -> Data {
        let cacheKey = namespacedKey(key, domain: domain)
        let memoryKey = cacheKey as NSString

        if policy != .reloadIgnoringCache, let cached = memoryDataCache.object(forKey: memoryKey) {
            hitCount += 1
            return cached as Data
        }

        if policy != .memoryOnly, let diskValue = try? loadDiskEntry(for: cacheKey, domain: domain) {
            if !isExpired(diskValue.metadata.expirationDate) {
                hitCount += 1
                memoryDataCache.setObject(diskValue.payload as NSData, forKey: memoryKey, cost: diskValue.payload.count)
                trackDataMemoryKey(cacheKey, domain: domain)
                try? touchDiskEntry(for: cacheKey, domain: domain, envelope: diskValue)
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
            memoryDataCache.setObject(payload as NSData, forKey: memoryKey, cost: payload.count)
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
            imageMemoryKeys.removeAll()
        }
        if domain == .all {
            memoryDataCache.removeAllObjects()
            dataMemoryKeys.removeAll()
            dataMemoryKeysByDomain.removeAll()
        } else if let keys = dataMemoryKeysByDomain[domain] {
            for key in keys {
                memoryDataCache.removeObject(forKey: key as NSString)
                dataMemoryKeys.remove(key)
            }
            dataMemoryKeysByDomain[domain] = Set<String>()
        }

        let domains = domain == .all ? [CacheDomain.image, .sourceMetadata, .networkResponse] : [domain]
        for target in domains where target != .all {
            try? fileManager.removeItem(at: directory(for: target))
            try? fileManager.createDirectory(at: directory(for: target), withIntermediateDirectories: true, attributes: nil)
        }
    }

    func stats() async -> CacheStats {
        CacheStats(
            memoryImageCount: imageMemoryKeys.count,
            memoryDataCount: dataMemoryKeys.count,
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
        dataMemoryKeys.insert(key)
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

    private func touchDiskEntry(for key: String, domain: CacheDomain, envelope: DiskCacheEnvelope) throws {
        let refreshed = DiskCacheEnvelope(
            metadata: CacheEntryMetadata(
                key: envelope.metadata.key,
                domain: envelope.metadata.domain,
                expirationDate: envelope.metadata.expirationDate,
                byteCount: envelope.metadata.byteCount,
                createdAt: envelope.metadata.createdAt,
                lastAccessedAt: .now
            ),
            payload: envelope.payload
        )
        let url = fileURL(for: key, domain: domain)
        let data = try JSONEncoder().encode(refreshed)
        try data.write(to: url, options: .atomic)
    }

    private func storeDiskEntry(payload: Data, for key: String, domain: CacheDomain, ttl: TimeInterval?) throws {
        let url = fileURL(for: key, domain: domain)
        let envelope = DiskCacheEnvelope(
            metadata: CacheEntryMetadata(
                key: key,
                domain: domain,
                expirationDate: ttl.map { Date().addingTimeInterval($0) },
                byteCount: payload.count,
                createdAt: .now,
                lastAccessedAt: .now
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
            maxBytes = 256 * 1_024 * 1_024
        case .sourceMetadata:
            maxBytes = 32 * 1_024 * 1_024
        case .networkResponse:
            maxBytes = 96 * 1_024 * 1_024
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

    private static func downsampledImage(data: Data, for url: URL, maxPixelSize: CGFloat = 2_400) -> UIImage? {
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
}
