//
//  RuntimeSourceRepository.swift
//  Mihon IOS
//

import Foundation

final class RuntimeSourceRepository: SourceRepository, SourceCatalogRuntime {
    private let fallback: InternalSourceRepository
    private let runtimes: [String: any SourceRuntime]

    init(fallback: InternalSourceRepository = InternalSourceRepository()) {
        self.fallback = fallback

        let kiryuuSource = fallback.sources().first { $0.id == "kiryuu-id" }!
        let kiryuuRuntime = NatsuIdSourceEngine(configuration: KiryuuSourceConfiguration(
            source: kiryuuSource,
            baseURL: "https://v1.kiryuu.to",
            rateLimit: 4,
            chapterListPageOverride: 1
        ))
        
        let asuraSource = fallback.sources().first { $0.id == "asura-en" }!
        let asuraRuntimeAPI = AsuraAPISourceEngine(
            source: asuraSource,
            baseURL: "https://asuracomic.net",
            apiBaseURL: "https://gg.asuracomic.net"
        )
        // Keep HTML engine available for future fallback or debugging (not registered here)
        _ = AsuraHTMLSourceEngine(source: asuraSource, baseURL: "https://asuracomic.net")
        
        self.runtimes = [kiryuuSource.id: kiryuuRuntime,
                         asuraSource.id: asuraRuntimeAPI]
    }

    func sources() -> [Source] {
        fallback.sources()
    }

    func mangas(for sourceID: String) -> [Manga] {
        fallback.mangas(for: sourceID)
    }

    func chapters(for mangaID: String) -> [Chapter] {
        fallback.chapters(for: mangaID)
    }

    func activeSources() -> [Source] {
        fallback.activeSources()
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
}
