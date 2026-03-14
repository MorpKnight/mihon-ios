//
//  InternalSourceRepository.swift
//  Mihon IOS
//

import Foundation

struct InternalSourceRepository: SourceRepository {
    private let sourcesData: [Source]
    private let mangaData: [Manga]
    private let chapterData: [Chapter]

    init(now: Date = .now) {
        let remote = Source(
            id: "mihon-directory",
            name: "Mihon Directory",
            kind: .remote,
            summary: "Internal JSON source catalog that mirrors the browse-first Mihon experience on iOS.",
            systemImage: "sparkle.magnifyingglass",
            language: .multi,
            isEnabled: true,
            isPinned: true,
            allowsAdultContent: false
        )
        let kiryuu = Source(
            id: "kiryuu-id",
            name: "Kiryuu",
            kind: .remote,
            summary: "Indonesian manga source powered by the reusable NatsuId runtime.",
            systemImage: "text.book.closed",
            language: .indonesian,
            isEnabled: true,
            isPinned: true,
            allowsAdultContent: false
        )
        let local = Source(
            id: "local-files",
            name: "Local Files",
            kind: .local,
            summary: "Portable local source scaffold for CBZ, EPUB, and imported reader demos.",
            systemImage: "internaldrive",
            language: .multi,
            isEnabled: true,
            isPinned: false,
            allowsAdultContent: false
        )

        let mangas = [
            Manga(
                id: "wind-breaker",
                sourceID: remote.id,
                title: "Wind Breaker",
                author: "Satoru Nii",
                summary: "A fast-moving delinquent story with team battles, long arcs, and a strong sense of momentum that translates well to a reader-first mobile flow.",
                genres: ["Action", "School", "Drama"],
                coverHexes: ["#5C8CFF", "#13213B"],
                coverURL: nil,
                statusText: "Ongoing"
            ),
            Manga(
                id: "blue-lock",
                sourceID: remote.id,
                title: "Blue Lock",
                author: "Muneyuki Kaneshiro",
                summary: "Competitive sports storytelling with aggressive pacing and a clean card-based presentation that works well for browse, detail, and continue-reading flows.",
                genres: ["Sports", "Drama"],
                coverHexes: ["#2F4D8F", "#141A2D"],
                coverURL: nil,
                statusText: "Ongoing"
            ),
            Manga(
                id: "local-demo-archive",
                sourceID: local.id,
                title: "Local Demo Archive",
                author: "Imported Bundle",
                summary: "A bundled local-source example that stands in for scanned archive support while the full importer pipeline is built.",
                genres: ["Local", "Archive"],
                coverHexes: ["#3C8D7B", "#162B27"],
                coverURL: nil,
                statusText: "Local"
            ),
        ]

        func makePages(prefix: String, accents: [String]) -> [ReaderPage] {
            accents.enumerated().map { index, accent in
                ReaderPage(
                    id: "\(prefix)-page-\(index + 1)",
                    index: index,
                    title: "Page \(index + 1)",
                    body: "This reader page is a lightweight iOS-native placeholder panel. It tracks progress, supports resume reading, and keeps the chapter navigation model explicit so the Android reader logic can be ported safely in later iterations.",
                    accentHex: accent,
                    assetKind: .text,
                    assetPath: nil,
                    remoteURL: nil
                )
            }
        }

        let chapters = [
            Chapter(id: "wind-breaker-174", mangaID: "wind-breaker", title: "Chapter 174", number: 174, releaseDate: now.addingTimeInterval(-86_400), isDownloaded: false, pages: makePages(prefix: "wind-breaker-174", accents: ["#5C8CFF", "#7CA8FF", "#A3C2FF"])),
            Chapter(id: "wind-breaker-173", mangaID: "wind-breaker", title: "Chapter 173", number: 173, releaseDate: now.addingTimeInterval(-172_800), isDownloaded: true, pages: makePages(prefix: "wind-breaker-173", accents: ["#1C5D99", "#2D79C7", "#7FAEEB"])),
            Chapter(id: "blue-lock-292", mangaID: "blue-lock", title: "Chapter 292", number: 292, releaseDate: now.addingTimeInterval(-43_200), isDownloaded: true, pages: makePages(prefix: "blue-lock-292", accents: ["#1D3F72", "#4165A8", "#9AB8FF"])),
            Chapter(id: "blue-lock-291", mangaID: "blue-lock", title: "Chapter 291", number: 291, releaseDate: now.addingTimeInterval(-129_600), isDownloaded: false, pages: makePages(prefix: "blue-lock-291", accents: ["#13233F", "#2A467D", "#6E90CC"])),
            Chapter(id: "local-demo-3", mangaID: "local-demo-archive", title: "Episode 3", number: 3, releaseDate: now.addingTimeInterval(-21_600), isDownloaded: true, pages: makePages(prefix: "local-demo-3", accents: ["#215B4E", "#3C8D7B", "#9FE1D1"])),
            Chapter(id: "local-demo-2", mangaID: "local-demo-archive", title: "Episode 2", number: 2, releaseDate: now.addingTimeInterval(-108_000), isDownloaded: true, pages: makePages(prefix: "local-demo-2", accents: ["#193A32", "#32685C", "#8BC3B7"])),
        ]

        self.sourcesData = [kiryuu, remote, local]
        self.mangaData = mangas
        self.chapterData = chapters
    }

    func sources() -> [Source] {
        sourcesData
    }

    func mangas(for sourceID: String) -> [Manga] {
        mangaData.filter { $0.sourceID == sourceID }.sorted { $0.title < $1.title }
    }

    func chapters(for mangaID: String) -> [Chapter] {
        chapterData
            .filter { $0.mangaID == mangaID }
            .sorted { $0.number > $1.number }
    }

    func activeSources() -> [Source] {
        sources().filter(\.isEnabled)
    }

    func popularManga(sourceID: String) async throws -> [Manga] {
        mangas(for: sourceID)
    }

    func latestManga(sourceID: String) async throws -> [Manga] {
        mangas(for: sourceID)
    }

    func searchManga(sourceID: String, query: String, filters: [SourceFilterValue]) async throws -> [Manga] {
        let lowered = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowered.isEmpty else { return mangas(for: sourceID) }
        return mangas(for: sourceID).filter {
            $0.title.localizedCaseInsensitiveContains(lowered) ||
            $0.author.localizedCaseInsensitiveContains(lowered) ||
            $0.genres.joined(separator: " ").localizedCaseInsensitiveContains(lowered)
        }
    }

    func mangaDetails(sourceID: String, mangaIDOrURL: String) async throws -> SourceMangaDetails {
        guard let manga = mangas(for: sourceID).first(where: { $0.id == mangaIDOrURL }) else {
            throw NSError(domain: "InternalSourceRepository", code: 404, userInfo: [NSLocalizedDescriptionKey: "Manga not found"])
        }
        return SourceMangaDetails(manga: manga)
    }

    func chapters(sourceID: String, manga: Manga) async throws -> SourceChapterDetails {
        SourceChapterDetails(chapters: chapters(for: manga.id))
    }

    func pages(sourceID: String, chapter: Chapter) async throws -> SourcePageAsset {
        SourcePageAsset(pages: chapter.pages, errorMessage: nil)
    }

    func genreTags(sourceID: String) async throws -> [GenreTag] {
        []
    }
}
