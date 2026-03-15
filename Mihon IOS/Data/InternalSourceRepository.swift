//
//  InternalSourceRepository.swift
//  Mihon IOS
//

import Foundation

struct InternalSourceRepository: SourceRepository {
    private let sourcesData: [Source]
    private let descriptorData: [SourceDescriptor]
    private let mangaData: [Manga]
    private let chapterData: [Chapter]

    init(now: Date = .now) {
        let remote = Source(
            id: "mihon-directory",
            name: "Mihon Directory",
            kind: .remote,
            engineFamily: .internalCatalog,
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
            engineFamily: .natsuId,
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
            engineFamily: .local,
            summary: "Portable local source entry point for CBZ, EPUB, ZIP, and imported reader files.",
            systemImage: "internaldrive",
            language: .multi,
            isEnabled: true,
            isPinned: false,
            allowsAdultContent: false
        )

        let madara = Source(
            id: "madaradex-en",
            name: "MadaraDex",
            kind: .remote,
            engineFamily: .madara,
            summary: "Madara-based source used to validate the new family runtime registry on iOS.",
            systemImage: "building.columns",
            language: .english,
            isEnabled: true,
            isPinned: false,
            allowsAdultContent: false
        )

        let themesia = Source(
            id: "ainzscansid-id",
            name: "Ainz Scans ID",
            kind: .remote,
            engineFamily: .mangaThemesia,
            summary: "MangaThemesia-based source used to validate descriptor-driven family support on iOS.",
            systemImage: "square.stack.3d.up",
            language: .indonesian,
            isEnabled: true,
            isPinned: false,
            allowsAdultContent: false
        )

        let asuraScans = Source(
            id: "asurascans-en",
            name: "Asura Scans",
            kind: .remote,
            engineFamily: .asuraScans,
            summary: "English source backed by a custom runtime for Asura's site and API flow.",
            systemImage: "bolt.horizontal.circle",
            language: .english,
            isEnabled: true,
            isPinned: true,
            allowsAdultContent: false
        )

        let mangabat = Source(
            id: "mangabat-en",
            name: "Mangabat",
            kind: .remote,
            engineFamily: .mangaBox,
            summary: "English MangaBox source using the Mangabat mirror flow.",
            systemImage: "books.vertical.circle",
            language: .english,
            isEnabled: true,
            isPinned: true,
            allowsAdultContent: false
        )

        let komikIndoID = Source(
            id: "komikindoid-id",
            name: "KomikIndoID",
            kind: .remote,
            engineFamily: .komikIndoID,
            summary: "Indonesian source with explicit parsed runtime based on the KomikIndoID extension.",
            systemImage: "text.book.closed.fill",
            language: .indonesian,
            isEnabled: true,
            isPinned: true,
            allowsAdultContent: false
        )

        let nhentai = Source(
            id: "nhentai-all",
            name: "NHentai",
            kind: .remote,
            engineFamily: .nhentai,
            summary: "NHentai all-language runtime with ID search, gallery metadata, and single-chapter reading flow.",
            systemImage: "eye.circle",
            language: .multi,
            isEnabled: true,
            isPinned: false,
            allowsAdultContent: true
        )

        let zeist = Source(
            id: "zeist-sample",
            name: "Zeist Sample",
            kind: .remote,
            engineFamily: .zeistManga,
            summary: "Representative entry for the ZeistManga family in the new source runtime registry.",
            systemImage: "sparkles.rectangle.stack",
            language: .english,
            isEnabled: true,
            isPinned: false,
            allowsAdultContent: false
        )

        let fmReader = Source(
            id: "fmreader-sample",
            name: "FMReader Sample",
            kind: .remote,
            engineFamily: .fmReader,
            summary: "Representative entry for the FMReader family runtime scaffolding.",
            systemImage: "book.pages",
            language: .japanese,
            isEnabled: true,
            isPinned: false,
            allowsAdultContent: false
        )

        let foolSlide = Source(
            id: "foolslide-sample",
            name: "FoolSlide Sample",
            kind: .remote,
            engineFamily: .foolSlide,
            summary: "Representative entry for the FoolSlide family runtime scaffolding.",
            systemImage: "doc.text.image",
            language: .english,
            isEnabled: true,
            isPinned: false,
            allowsAdultContent: false
        )

        let newToki = Source(
            id: "newtoki-sample",
            name: "NewToki Sample",
            kind: .remote,
            engineFamily: .newToki,
            summary: "Representative entry for the NewToki family runtime scaffolding.",
            systemImage: "rectangle.stack.badge.person.crop",
            language: .japanese,
            isEnabled: true,
            isPinned: false,
            allowsAdultContent: false
        )

        let custom = Source(
            id: "custom-http-sample",
            name: "Custom HTTP Sample",
            kind: .remote,
            engineFamily: .customParsed,
            summary: "Bucket for custom HttpSource and ParsedHttpSource adapters pending subfamily clustering.",
            systemImage: "network.badge.shield.half.filled",
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
        ]

        self.sourcesData = [kiryuu, asuraScans, mangabat, komikIndoID, nhentai, remote, local, madara, themesia, zeist, fmReader, foolSlide, newToki, custom]
        self.descriptorData = [
            Self.makeDescriptor(for: remote, baseURL: nil, capabilities: [.popular, .latest, .search, .mangaDetail, .chapterList], featureFlags: ["catalog-only"], overrides: [:]),
            Self.makeDescriptor(for: kiryuu, baseURL: "https://v1.kiryuu.to", capabilities: [.popular, .latest, .search, .mangaDetail, .chapterList, .pageList, .filters, .reader], featureFlags: ["runtime-live", "natsuid-v1"], overrides: [:]),
            Self.makeDescriptor(for: asuraScans, baseURL: "https://asuracomic.net", capabilities: [.popular, .latest, .search, .mangaDetail, .chapterList, .pageList, .filters, .reader], featureFlags: ["runtime-live", "source-asura"], overrides: ["apiURL": "https://gg.asuracomic.net/api"]),
            Self.makeDescriptor(for: mangabat, baseURL: "https://www.mangabats.com", capabilities: [.popular, .latest, .search, .mangaDetail, .chapterList, .pageList, .filters, .reader], featureFlags: ["runtime-live", "family-mangabox"], overrides: [:]),
            Self.makeDescriptor(for: komikIndoID, baseURL: "https://komikindo.ch", capabilities: [.popular, .latest, .search, .mangaDetail, .chapterList, .pageList, .filters, .reader], featureFlags: ["runtime-live", "source-komikindoid"], overrides: ["dateFormat": "MMM d, yyyy"]),
            Self.makeDescriptor(for: nhentai, baseURL: "https://nhentai.net", capabilities: [.popular, .latest, .search, .mangaDetail, .chapterList, .pageList, .filters, .reader], featureFlags: ["runtime-live", "source-nhentai"], overrides: ["languagePath": "", "searchIDPrefix": "id:"]),
            Self.makeDescriptor(for: local, baseURL: nil, capabilities: [.mangaDetail, .chapterList, .pageList, .reader], featureFlags: ["imported-content"], overrides: [:]),
            Self.makeDescriptor(for: madara, baseURL: "https://madaradex.org", capabilities: [.popular, .latest, .search, .mangaDetail, .chapterList, .pageList, .filters, .reader], featureFlags: ["runtime-live", "family-madara"], overrides: ["mangaSubPath": "title", "dateFormat": "MMM d, yyyy"]),
            Self.makeDescriptor(for: themesia, baseURL: "https://ainzscans01.com", capabilities: [.popular, .latest, .search, .mangaDetail, .chapterList, .pageList, .filters, .reader], featureFlags: ["runtime-live", "family-mangathemesia"], overrides: ["mangaSubPath": "series", "dateFormat": "MMMM dd, yyyy", "hasProjectPage": "true"]),
            Self.makeDescriptor(for: zeist, baseURL: "https://example-zeist.invalid", capabilities: [.popular, .latest, .search, .mangaDetail, .chapterList, .pageList, .reader], featureFlags: ["family-scaffold"], overrides: [:]),
            Self.makeDescriptor(for: fmReader, baseURL: "https://example-fmreader.invalid", capabilities: [.popular, .latest, .search, .mangaDetail, .chapterList, .pageList, .reader], featureFlags: ["family-scaffold"], overrides: [:]),
            Self.makeDescriptor(for: foolSlide, baseURL: "https://example-foolslide.invalid", capabilities: [.latest, .search, .mangaDetail, .chapterList, .pageList, .reader], featureFlags: ["family-scaffold"], overrides: [:]),
            Self.makeDescriptor(for: newToki, baseURL: "https://example-newtoki.invalid", capabilities: [.popular, .latest, .search, .mangaDetail, .chapterList, .pageList, .filters, .reader], featureFlags: ["family-scaffold"], overrides: [:]),
            Self.makeDescriptor(for: custom, baseURL: nil, capabilities: [.search, .mangaDetail, .chapterList, .pageList, .reader], featureFlags: ["custom-adapter-pending"], overrides: [:]),
        ]
        self.mangaData = mangas
        self.chapterData = chapters
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

    private static func makeDescriptor(
        for source: Source,
        baseURL: String?,
        capabilities: Set<SourceCapability>,
        featureFlags: [String],
        overrides: [String: String]
    ) -> SourceDescriptor {
        let requestPolicy = SourceRequestPolicy(
            rateLimit: source.engineFamily == .natsuId ? 4 : 2,
            referrer: baseURL.map { "\($0)/" },
            userAgent: nil,
            requiresCookies: source.engineFamily == .madara || source.engineFamily == .customParsed
        )
        let context = baseURL.map {
            SourceRuntimeContext(
                baseURL: $0,
                language: source.language,
                authMode: .none,
                requestPolicy: requestPolicy
            )
        }
        let filterSchema: [SourceFilterSchema] = capabilities.contains(.filters)
            ? [
                SourceFilterSchema(id: "\(source.id)-sort", title: "Sort", kind: "select"),
                SourceFilterSchema(id: "\(source.id)-genre", title: "Genre", kind: "multi-select"),
            ]
            : []
        let preferenceSchema: [SourcePreferenceSchema] = [
            SourcePreferenceSchema(id: "\(source.id)-family", title: "Engine Family", detail: source.engineFamily.title),
        ]

        return SourceDescriptor(
            id: "descriptor::\(source.id)",
            sourceID: source.id,
            name: source.name,
            engineFamily: source.engineFamily,
            kind: source.kind,
            language: source.language,
            baseURL: baseURL,
            capabilities: capabilities,
            featureFlags: featureFlags,
            overrides: overrides,
            context: context,
            filterSchema: filterSchema,
            preferenceSchema: preferenceSchema,
            packageName: nil,
            version: nil,
            languageCode: nil,
            origin: "built-in",
            supportStatus: featureFlags.contains("runtime-live") ? .live : (featureFlags.contains("family-scaffold") ? .planned : .unsupported)
        )
    }
}
