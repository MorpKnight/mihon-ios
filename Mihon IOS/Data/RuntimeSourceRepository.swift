//
//  RuntimeSourceRepository.swift
//  Mihon IOS
//

import Foundation

final class RuntimeSourceRepository: SourceRepository, SourceCatalogRuntime {
    private let fallback: InternalSourceRepository
    private let sourcesData: [Source]
    private let descriptorData: [SourceDescriptor]
    private let runtimes: [String: any SourceRuntime]

    init(
        repoRecords: [SourceRepoRecord] = [],
        fallback: InternalSourceRepository = InternalSourceRepository()
    ) {
        self.fallback = fallback

        let registry = SourceRegistryBuilder().build(
            internalSources: fallback.sources(),
            internalDescriptors: fallback.descriptors(),
            repoRecords: repoRecords
        )
        self.sourcesData = registry.0
        self.descriptorData = registry.1
        self.runtimes = Self.buildRuntimes(sources: registry.0, descriptors: registry.1)
    }

    func sources() -> [Source] {
        sourcesData
    }

    func descriptors() -> [SourceDescriptor] {
        descriptorData
    }

    func descriptor(for sourceID: String) -> SourceDescriptor? {
        descriptorData.first { $0.sourceID == sourceID }
    }

    func mangas(for sourceID: String) -> [Manga] {
        fallback.mangas(for: sourceID)
    }

    func chapters(for mangaID: String) -> [Chapter] {
        fallback.chapters(for: mangaID)
    }

    func activeSources() -> [Source] {
        sourcesData.filter(\.isEnabled)
    }

    func popularManga(sourceID: String) async throws -> [Manga] {
        guard let runtime = runtimes[sourceID] else {
            return try await fallback.popularManga(sourceID: sourceID)
        }
        return try await runtime.popularManga(page: 1)
    }

    func latestManga(sourceID: String) async throws -> [Manga] {
        guard let runtime = runtimes[sourceID] else {
            return try await fallback.latestManga(sourceID: sourceID)
        }
        return try await runtime.latestManga(page: 1)
    }

    func searchManga(sourceID: String, query: String, filters: [SourceFilterValue]) async throws -> [Manga] {
        guard let runtime = runtimes[sourceID] else {
            return try await fallback.searchManga(sourceID: sourceID, query: query, filters: filters)
        }
        return try await runtime.searchManga(SourceSearchRequest(query: query, page: 1, filters: filters))
    }

    func mangaDetails(sourceID: String, mangaIDOrURL: String) async throws -> SourceMangaDetails {
        guard let runtime = runtimes[sourceID] else {
            return try await fallback.mangaDetails(sourceID: sourceID, mangaIDOrURL: mangaIDOrURL)
        }
        return try await runtime.mangaDetails(mangaIDOrURL: mangaIDOrURL)
    }

    func chapters(sourceID: String, manga: Manga) async throws -> SourceChapterDetails {
        guard let runtime = runtimes[sourceID] else {
            return try await fallback.chapters(sourceID: sourceID, manga: manga)
        }
        return try await runtime.chapters(for: manga)
    }

    func pages(sourceID: String, chapter: Chapter) async throws -> SourcePageAsset {
        guard let runtime = runtimes[sourceID] else {
            return try await fallback.pages(sourceID: sourceID, chapter: chapter)
        }
        return try await runtime.pages(for: chapter)
    }

    func genreTags(sourceID: String) async throws -> [GenreTag] {
        guard let runtime = runtimes[sourceID] else {
            return try await fallback.genreTags(sourceID: sourceID)
        }
        return try await runtime.genreTags()
    }

    private static func buildRuntimes(
        sources: [Source],
        descriptors: [SourceDescriptor]
    ) -> [String: any SourceRuntime] {
        var runtimes: [String: any SourceRuntime] = [:]

        for descriptor in descriptors {
            guard let source = sources.first(where: { $0.id == descriptor.sourceID }) else {
                continue
            }

            switch descriptor.engineFamily {
            case .natsuId:
                guard let context = descriptor.context else { continue }
                runtimes[source.id] = NatsuIdSourceEngine(
                    configuration: KiryuuSourceConfiguration(
                        source: source,
                        baseURL: context.baseURL,
                        rateLimit: max(context.requestPolicy.rateLimit, 1),
                        chapterListPageOverride: 1
                    )
                )
            case .asuraScans:
                let baseURL = descriptor.context?.baseURL ?? descriptor.baseURL ?? "https://asuracomic.net"
                let apiBaseURL = baseURL.contains("asuracomic.net")
                    ? "https://gg.asuracomic.net"
                    : baseURL
                runtimes[source.id] = AsuraAPISourceEngine(
                    source: source,
                    baseURL: baseURL,
                    apiBaseURL: apiBaseURL
                )
            default:
                continue
            }
        }

        return runtimes
    }
}
