//
//  RuntimeSourceRepository.swift
//  Mihon IOS
//

import Foundation

final class RuntimeSourceRepository: SourceRepository, SourceCatalogRuntime {
    private let fallback: InternalSourceRepository
    private let runtimes: [String: any SourceRuntime]

struct NatsuIdRuntimeFactory: SourceEngine {
    let family: SourceEngineFamily = .natsuId

    func makeRuntime(from descriptor: SourceDescriptor, source: Source) throws -> any SourceRuntime {
        guard let context = descriptor.context else {
            throw RuntimeSourceError.invalidResponse
        }
        return NatsuIdSourceEngine(configuration: KiryuuSourceConfiguration(
            source: source,
            baseURL: context.baseURL,
            rateLimit: max(context.requestPolicy.rateLimit, 1),
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
}

final class MadaraSourceEngine: SourceRuntime {
    let source: Source

    private let descriptor: SourceDescriptor
    private let session: URLSession
    private let rateLimiter: SourceRateLimiter
    private let dateFormatter: DateFormatter

    init(source: Source, descriptor: SourceDescriptor, session: URLSession = .shared) {
        self.source = source
        self.descriptor = descriptor
        self.session = session
        self.rateLimiter = SourceRateLimiter(requestsPerSecond: max(descriptor.context?.requestPolicy.rateLimit ?? 2, 1))
        self.dateFormatter = DateFormatter()
        self.dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        self.dateFormatter.dateFormat = descriptor.overrides["dateFormat"] ?? "MMM d, yyyy"
    }

    func popularManga(page: Int) async throws -> [Manga] {
        let url = archiveURL(page: page, queryItems: [URLQueryItem(name: "m_orderby", value: "views")])
        let html = try await getHTML(url: url)
        return parseArchiveManga(from: html)
    }

    func latestManga(page: Int) async throws -> [Manga] {
        let url = archiveURL(page: page, queryItems: [URLQueryItem(name: "m_orderby", value: "latest")])
        let html = try await getHTML(url: url)
        return parseArchiveManga(from: html)
    }

    func searchManga(_ request: SourceSearchRequest) async throws -> [Manga] {
        if let deepLink = deepLinkURL(from: request.query) {
            let html = try await getHTML(url: deepLink)
            let manga = try parseMangaDetails(html: html, url: deepLink)
            return [manga]
        }

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "s", value: request.query),
            URLQueryItem(name: "post_type", value: "wp-manga"),
        ]
        for filter in request.filters {
            switch filter {
            case .sort(let value):
                if !value.isEmpty { queryItems.append(URLQueryItem(name: "m_orderby", value: value)) }
            case .genreInclude(_, let slugs):
                queryItems.append(contentsOf: slugs.map { URLQueryItem(name: "genre[]", value: $0) })
            default:
                break
            }
        }
        let url = rootURL(queryItems: queryItems)
        let html = try await getHTML(url: url)
        return parseArchiveManga(from: html)
    }

    func mangaDetails(mangaIDOrURL: String) async throws -> SourceMangaDetails {
        let url = try resolveMangaURL(from: mangaIDOrURL)
        let html = try await getHTML(url: url)
        return SourceMangaDetails(manga: try parseMangaDetails(html: html, url: url))
    }

    func chapters(for manga: Manga) async throws -> SourceChapterDetails {
        let url = try resolveMangaURL(from: manga.id)
        let html = try await getHTML(url: url)
        var chapters = parseChapters(from: html, mangaID: manga.id)
        if chapters.isEmpty, let mangaID = firstMatch(in: html, pattern: "id=[\"']manga-chapters-holder[^>]*data-id=[\"'](\\d+)[\"']") {
            let ajaxHTML = try await fetchChapterListHTML(mangaURL: url, mangaNumericID: mangaID)
            chapters = parseChapters(from: ajaxHTML, mangaID: manga.id)
        }
        return SourceChapterDetails(chapters: chapters)
    }

    func pages(for chapter: Chapter) async throws -> SourcePageAsset {
        guard let url = URL(string: chapter.id) else {
            throw RuntimeSourceError.chapterPagesMissing
        }
        let html = try await getHTML(url: url)
        let imageURLs = parsePageURLs(from: html)
        guard !imageURLs.isEmpty else { throw RuntimeSourceError.parserEmpty }
        return SourcePageAsset(
            pages: imageURLs.enumerated().map { index, imageURL in
                ReaderPage(
                    id: "\(chapter.id)#page-\(index + 1)",
                    index: index,
                    title: "Page \(index + 1)",
                    body: "",
                    accentHex: NatsuIdSourceEngine.paletteColor(seed: "\(chapter.id)-\(index)"),
                    assetKind: .image,
                    assetPath: nil,
                    remoteURL: imageURL
                )
            },
            errorMessage: nil
        )
    }

    func genreTags() async throws -> [GenreTag] {
        let url = rootURL(queryItems: [
            URLQueryItem(name: "s", value: "genre"),
            URLQueryItem(name: "post_type", value: "wp-manga"),
        ])
        let html = try await getHTML(url: url)
        let tags = allMatchPairs(in: html, pattern: "<input[^>]*type=[\"']checkbox[\"'][^>]*value=[\"']([^\"']+)[\"'][^>]*>\\s*<label[^>]*>([^<]+)</label>")
        return tags.map { GenreTag(name: decodeHTML($0.1), slug: $0.0) }
    }

    private func archiveURL(page: Int, queryItems: [URLQueryItem]) -> URL {
        let path = archivePath(page: page)
        return components(path: path, queryItems: queryItems).url!
    }

    private func rootURL(queryItems: [URLQueryItem]) -> URL {
        components(path: "", queryItems: queryItems).url!
    }

    private func archivePath(page: Int) -> String {
        let mangaSubPath = descriptor.overrides["mangaSubPath"] ?? "manga"
        if page <= 1 {
            return "/\(mangaSubPath)/"
        }
        return "/\(mangaSubPath)/page/\(page)/"
    }

    private func components(path: String, queryItems: [URLQueryItem]) -> URLComponents {
        var components = URLComponents(string: descriptor.context?.baseURL ?? "")!
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components
    }

    private func deepLinkURL(from query: String) -> URL? {
        guard
            let url = URL(string: query.trimmingCharacters(in: .whitespacesAndNewlines)),
            let base = URL(string: descriptor.context?.baseURL ?? ""),
            url.host == base.host
        else {
            return nil
        }
        return url
    }

    private func resolveMangaURL(from mangaIDOrURL: String) throws -> URL {
        if let url = URL(string: mangaIDOrURL), url.scheme?.hasPrefix("http") == true {
            return url
        }

        let slug = mangaIDOrURL.components(separatedBy: "::").last ?? mangaIDOrURL
        let mangaSubPath = descriptor.overrides["mangaSubPath"] ?? "manga"
        guard let url = URL(string: "\(descriptor.context?.baseURL ?? "")/\(mangaSubPath)/\(slug)/") else {
            throw RuntimeSourceError.mangaNotFound
        }
        return url
    }

    private func fetchChapterListHTML(mangaURL: URL, mangaNumericID: String) async throws -> String {
        let oldEndpointBody = "action=manga_get_chapters&manga=\(mangaNumericID)"
        if let html = try await postHTML(url: URL(string: "\(descriptor.context?.baseURL ?? "")/wp-admin/admin-ajax.php")!, body: oldEndpointBody) {
            if html.localizedCaseInsensitiveContains("wp-manga-chapter") {
                return html
            }
        }
        let fallbackURL = mangaURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/ajax/chapters"
        guard let url = URL(string: fallbackURL) else { throw RuntimeSourceError.invalidResponse }
        return try await postHTML(url: url, body: nil) ?? ""
    }

    private func parseArchiveManga(from html: String) -> [Manga] {
        let blocks = allMatches(
            in: html,
            pattern: "(<div[^>]+(?:page-item-detail|c-tabs-item__content|manga__item)[\\s\\S]*?</div>\\s*</div>)",
            options: [.caseInsensitive]
        )
        var items: [Manga] = []
        var seen = Set<String>()
        for block in blocks {
            guard
                let href = firstMatch(in: block, pattern: "href=[\"']([^\"']+)[\"']"),
                let title = firstMatch(in: block, pattern: "<a[^>]*href=[\"'][^\"']+[\"'][^>]*>([^<]+)</a>")
                    ?? firstMatch(in: block, pattern: "<h3[^>]*>\\s*<a[^>]*>([^<]+)</a>")
            else { continue }
            let absoluteURL = absolutize(href)
            let slug = slugFromURLString(absoluteURL)
            guard !slug.isEmpty, seen.insert(slug).inserted else { continue }
            let imageURL = firstImageURL(in: block)
            items.append(Manga(
                id: "\(source.id)::\(slug)",
                sourceID: source.id,
                title: decodeHTML(title),
                author: "Unknown",
                summary: "Madara family source entry.",
                genres: [],
                coverHexes: NatsuIdSourceEngine.palette(for: slug),
                coverURL: imageURL,
                statusText: "Unknown"
            ))
        }
        return items
    }
}
