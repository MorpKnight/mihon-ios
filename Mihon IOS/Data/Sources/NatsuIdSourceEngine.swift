//
//  NatsuIdSourceEngine.swift
//  Mihon IOS
//

import Foundation

final class NatsuIdSourceEngine: SourceRuntime {
    let source: Source

    private let configuration: NatsuIdSourceConfiguration
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let rateLimiter: SourceRateLimiter
    private var nonceCache: String?
    private var genreCache: [GenreTag] = []

    // MARK: - Debug logging (only in DEBUG builds)
    private func debugLog(_ items: @autoclosure () -> String) {
#if DEBUG
        print("[NatsuId] \(items())")
#endif
    }

    init(configuration: NatsuIdSourceConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.source = configuration.source
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = [
            "User-Agent": SourceEngineUtilities.defaultUserAgent,
            "Accept-Language": "en-US,en;q=0.9",
            "Accept": "*/*"
        ]
        self.session = URLSession(configuration: config)
        self.rateLimiter = SourceRateLimiter(requestsPerSecond: configuration.rateLimit)
    }

    func popularManga(page: Int) async throws -> [Manga] {
        try await searchManga(SourceSearchRequest(
            query: "",
            page: page,
            filters: [.sort("popular"), .orderAscending(false)]
        ))
    }

    func latestManga(page: Int) async throws -> [Manga] {
        try await searchManga(SourceSearchRequest(
            query: "",
            page: page,
            filters: [.sort("updated"), .orderAscending(false)]
        ))
    }

    func searchManga(_ request: SourceSearchRequest) async throws -> [Manga] {
        if let deepLinkSlug = Self.deepLinkSlug(from: request.query, baseURL: configuration.baseURL) {
            return try await fetchMangaList(slugs: [deepLinkSlug])
        }

        let nonce = try await fetchNonce()
        let html = try await postAdvancedSearch(request: request, nonce: nonce)
        let slugs = Self.extractSlugs(from: html, baseURL: configuration.baseURL)
        guard !slugs.isEmpty else { return [] }
        return try await fetchMangaList(slugs: slugs)
    }

    func mangaDetails(mangaIDOrURL: String) async throws -> SourceMangaDetails {
        if let runtimeID = Self.parseRuntimeMangaID(mangaIDOrURL) {
            let manga = try await fetchManga(id: runtimeID.id, slug: runtimeID.slug, appendIdentifier: false)
            return SourceMangaDetails(manga: manga)
        }

        if let slug = Self.deepLinkSlug(from: mangaIDOrURL, baseURL: configuration.baseURL) {
            guard let manga = try await fetchMangaList(slugs: [slug]).first else {
                throw RuntimeSourceError.mangaNotFound
            }
            return SourceMangaDetails(manga: manga)
        }

        let slug = Self.parseSlugFromFallbackID(mangaIDOrURL)
        guard let manga = try await fetchMangaList(slugs: [slug]).first else {
            throw RuntimeSourceError.mangaNotFound
        }
        return SourceMangaDetails(manga: manga)
    }

    func chapters(for manga: Manga) async throws -> SourceChapterDetails {
        let runtimeID = try await resolveRuntimeMangaID(for: manga)
        var components = URLComponents(string: configuration.baseURL + "/wp-admin/admin-ajax.php")!
        components.queryItems = [
            URLQueryItem(name: "manga_id", value: String(runtimeID.id)),
            URLQueryItem(name: "page", value: String(configuration.chapterListPageOverride ?? 999)),
            URLQueryItem(name: "action", value: "chapter_list"),
        ]
        let html = try await getHTML(url: components.url!)
        let chapters = Self.extractChapters(from: html, mangaID: manga.id, baseURL: configuration.baseURL)
        return SourceChapterDetails(chapters: chapters)
    }

    func pages(for chapter: Chapter) async throws -> SourcePageAsset {
        guard let url = URL(string: chapter.id) else {
            throw RuntimeSourceError.chapterPagesMissing
        }
        let html = try await getHTML(url: url)
        let imageURLs = Self.extractPageImageURLs(from: html, baseURL: configuration.baseURL)
        guard !imageURLs.isEmpty else {
            if Self.detectBlockedImageHosts(in: html) {
                throw RuntimeSourceError.blockedImageHost
            }
            throw RuntimeSourceError.parserEmpty
        }
        let pages = imageURLs.enumerated().map { index, imageURL in
            ReaderPage(
                id: "\(chapter.id)#page-\(index + 1)",
                index: index,
                title: "Page \(index + 1)",
                body: "",
                accentHex: SourceEngineUtilities.paletteColor(seed: "\(chapter.id)-\(index)"),
                assetKind: .image,
                assetPath: nil,
                remoteURL: imageURL
            )
        }
        return SourcePageAsset(pages: pages, errorMessage: nil)
    }

    func genreTags() async throws -> [GenreTag] {
        if !genreCache.isEmpty {
            return genreCache
        }

        var components = URLComponents(string: configuration.baseURL + "/wp-json/wp/v2/genre")!
        components.queryItems = [
            URLQueryItem(name: "per_page", value: "100"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "orderby", value: "count"),
            URLQueryItem(name: "order", value: "desc"),
        ]
        let data = try await getData(url: components.url!, contentType: nil)
        let terms = try decoder.decode([GenreTermDTO].self, from: data)
        let tags = terms.map { GenreTag(name: SourceEngineUtilities.decodeHTML($0.name), slug: $0.slug) }
        genreCache = tags
        return tags
    }

    // MARK: - Private helpers

    private func fetchNonce() async throws -> String {
        debugLog("fetchNonce() start")

        if let nonceCache, !nonceCache.isEmpty {
            return nonceCache
        }

        let url = URL(string: configuration.baseURL + "/wp-admin/admin-ajax.php?type=search_form&action=get_nonce")!
        debugLog("GET nonce from: \(url.absoluteString)")
        let html = try await getHTML(url: url)
        guard let nonce = Self.extractNonce(from: html) else {
            throw RuntimeSourceError.nonceMissing
        }
        debugLog("Nonce extracted: \(nonce.prefix(12))…")
        nonceCache = nonce
        return nonce
    }

    private func postAdvancedSearch(request: SourceSearchRequest, nonce: String) async throws -> String {
        debugLog("postAdvancedSearch(page: \(request.page)) start")

        let boundary = "MihonBoundary-\(UUID().uuidString)"
        var urlRequest = URLRequest(url: URL(string: configuration.baseURL + "/wp-admin/admin-ajax.php?action=advanced_search")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(configuration.baseURL + "/", forHTTPHeaderField: "Referer")

        debugLog("POST advanced_search → \(urlRequest.url?.absoluteString ?? "<nil>")")

        let sortValue = request.filters.compactMap { filter -> String? in
            if case let .sort(value) = filter { return value }
            return nil
        }.last ?? "popular"
        let orderAscending = request.filters.compactMap { filter -> Bool? in
            if case let .orderAscending(value) = filter { return value }
            return nil
        }.last ?? false
        let selectedTypes = request.filters.compactMap { filter -> [String]? in
            if case let .types(values) = filter { return values }
            return nil
        }.last ?? []
        let includeGenres = request.filters.compactMap { filter -> (String, [String])? in
            if case let .genreInclude(mode, slugs) = filter { return (mode, slugs) }
            return nil
        }.last ?? ("OR", [])
        let excludeGenres = request.filters.compactMap { filter -> (String, [String])? in
            if case let .genreExclude(mode, slugs) = filter { return (mode, slugs) }
            return nil
        }.last ?? ("OR", [])

        let fields: [(String, String)] = [
            ("nonce", nonce),
            ("inclusion", includeGenres.0),
            ("exclusion", excludeGenres.0),
            ("page", String(max(request.page, 1))),
            ("genre", Self.jsonArray(includeGenres.1)),
            ("genre_exclude", Self.jsonArray(excludeGenres.1)),
            ("author", "[]"),
            ("artist", "[]"),
            ("project", "0"),
            ("type", Self.jsonArray(selectedTypes)),
            ("order", orderAscending ? "asc" : "desc"),
            ("orderby", sortValue),
            ("query", request.query.trimmingCharacters(in: .whitespacesAndNewlines)),
        ]

        urlRequest.httpBody = Self.multipartBody(fields: fields, boundary: boundary)

        let data = try await perform(urlRequest)
        debugLog("advanced_search HTML preview: \(String(data: data.prefix(512), encoding: .utf8) ?? "<non-utf8>")")
        guard let html = String(data: data, encoding: .utf8) else {
            throw RuntimeSourceError.invalidResponse
        }
        return html
    }

    private func fetchMangaList(slugs: [String]) async throws -> [Manga] {
        var components = URLComponents(string: configuration.baseURL + "/wp-json/wp/v2/manga")!
        components.queryItems = slugs.map { URLQueryItem(name: "slug[]", value: $0) }
        components.queryItems?.append(URLQueryItem(name: "per_page", value: String(slugs.count + 1)))
        components.queryItems?.append(URLQueryItem(name: "_embed", value: nil))

        let data = try await getData(url: components.url!, contentType: "application/json")
        let response = try decoder.decode([NatsuMangaDTO].self, from: data)
        let bySlug = Dictionary(uniqueKeysWithValues: response.map { ($0.slug, $0) })

        return slugs.compactMap { slug in
            guard let entry = bySlug[slug], !entry.isNovel else { return nil }
            return mapManga(entry, appendIdentifier: false)
        }
    }

    private func fetchManga(id: Int, slug: String, appendIdentifier: Bool) async throws -> Manga {
        var components = URLComponents(string: configuration.baseURL + "/wp-json/wp/v2/manga/\(id)")!
        components.queryItems = [URLQueryItem(name: "_embed", value: nil)]
        let data = try await getData(url: components.url!, contentType: "application/json")
        let response = try decoder.decode(NatsuMangaDTO.self, from: data)
        guard !response.isNovel else {
            throw RuntimeSourceError.mangaNotFound
        }
        return mapManga(response, appendIdentifier: appendIdentifier || response.slug != slug)
    }

    private func resolveRuntimeMangaID(for manga: Manga) async throws -> (id: Int, slug: String) {
        if let runtime = Self.parseRuntimeMangaID(manga.id) {
            return runtime
        }

        if let id = Self.extractIdentifier(from: manga.summary) {
            return (id, Self.parseSlugFromFallbackID(manga.id))
        }

        let details = try await mangaDetails(mangaIDOrURL: manga.id)
        guard let runtime = Self.parseRuntimeMangaID(details.manga.id) else {
            throw RuntimeSourceError.mangaNotFound
        }
        return runtime
    }

    private func getHTML(url: URL) async throws -> String {
        debugLog("GET HTML: \(url.absoluteString)")

        let data = try await getData(url: url, contentType: nil)
        guard let html = String(data: data, encoding: .utf8) else {
            throw RuntimeSourceError.invalidResponse
        }
        debugLog("HTML preview: \(html.prefix(256))…")
        return html
    }

    private func getData(url: URL, contentType: String?) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(configuration.baseURL + "/", forHTTPHeaderField: "Referer")
        request.setValue(SourceEngineUtilities.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Accept")
        }
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let maxAttempts = 3
        var lastError: Error?
        for attempt in 1...maxAttempts {
            await rateLimiter.waitTurn()
            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    debugLog("No HTTPURLResponse for: \(request.url?.absoluteString ?? "<nil>")")
                    throw RuntimeSourceError.invalidResponse
                }

                let urlString = request.url?.absoluteString ?? "<nil>"
                let status = httpResponse.statusCode
                let contentType = httpResponse.allHeaderFields["Content-Type"] as? String ?? "<unknown>"
                let preview = String(data: data.prefix(512), encoding: .utf8) ?? "<non-utf8>"
                debugLog("HTTP \(status) • \(contentType) • \(urlString)\n↳ Body preview: \(preview)")

                if !(200..<300).contains(status) {
                    if attempt < maxAttempts && (status == 403 || status == 429 || status == 503) {
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        continue
                    }
                    throw RuntimeSourceError.invalidResponse
                }
                return data
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }
            }
        }
        throw lastError ?? RuntimeSourceError.invalidResponse
    }

    private func mapManga(_ entry: NatsuMangaDTO, appendIdentifier: Bool) -> Manga {
        let terms = entry.embedded.termGroups.flatMap { $0 }
        let author = terms.filter { $0.taxonomy == "series-author" }.map { SourceEngineUtilities.decodeHTML($0.name) }.joined(separator: ", ")
        let artist = terms.filter { $0.taxonomy == "artist" }.map { SourceEngineUtilities.decodeHTML($0.name) }.joined(separator: ", ")
        let genres = Array(Set(
            terms
                .filter { $0.taxonomy == "genre" || $0.taxonomy == "type" }
                .map { SourceEngineUtilities.decodeHTML($0.name) }
        )).sorted()
        let statusTerms = terms.filter { $0.taxonomy == "status" }.map { SourceEngineUtilities.decodeHTML($0.name) }
        let summaryBody = SourceEngineUtilities.stripHTML(entry.content.rendered)
        let summary = appendIdentifier ? "\(summaryBody)\n\nID: \(entry.id)" : summaryBody
        let authorLine = [author, artist].filter { !$0.isEmpty }.joined(separator: " • ")

        return Manga(
            id: "\(source.id)::\(entry.id)::\(entry.slug)",
            sourceID: source.id,
            title: SourceEngineUtilities.decodeHTML(entry.title.rendered),
            author: authorLine.isEmpty ? "Unknown" : authorLine,
            summary: summary,
            genres: genres,
            coverHexes: SourceEngineUtilities.palette(for: entry.slug),
            coverURL: entry.embedded.featuredMedia.first?.sourceURL ?? Self.extractOGImage(from: entry.yoastHead),
            statusText: statusTerms.first ?? "Unknown"
        )
    }

    // MARK: - NatsuId-specific static helpers

    private static func multipartBody(fields: [(String, String)], boundary: String) -> Data {
        var data = Data()
        for (name, value) in fields {
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            data.append("\(value)\r\n".data(using: .utf8)!)
        }
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return data
    }

    private static func jsonArray(_ values: [String]) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: values, options: []),
            let string = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return string
    }

    private static func deepLinkSlug(from query: String, baseURL: String) -> String? {
        guard
            let url = URL(string: query.trimmingCharacters(in: .whitespacesAndNewlines)),
            let base = URL(string: baseURL),
            url.host == base.host
        else {
            return nil
        }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, parts[0] == "manga" else { return nil }
        return parts[1]
    }

    private static func parseRuntimeMangaID(_ value: String) -> (id: Int, slug: String)? {
        let components = value.components(separatedBy: "::")
        guard components.count >= 3, let numericID = Int(components[1]) else { return nil }
        return (numericID, components[2])
    }

    private static func parseSlugFromFallbackID(_ value: String) -> String {
        if let parsed = parseRuntimeMangaID(value) {
            return parsed.slug
        }
        return value.components(separatedBy: "::").last ?? value
    }

    private static func extractIdentifier(from text: String) -> Int? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let regex = try? NSRegularExpression(pattern: "ID:\\s*(\\d+)")
        guard
            let match = regex?.firstMatch(in: text, range: range),
            let idRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return Int(text[idRange])
    }

    private static func extractNonce(from html: String) -> String? {
        let pattern = "name=[\"']search_nonce[\"'][^>]*value=[\"']([^\"']+)"
        return SourceEngineUtilities.firstMatch(in: html, pattern: pattern)
    }

    private static func extractSlugs(from html: String, baseURL: String) -> [String] {
        let pattern = "href=[\"']([^\"']+/manga/[^\"']+)[\"']"
        let matches = SourceEngineUtilities.allMatches(in: html, pattern: pattern)
        var slugs: [String] = []
        var seen = Set<String>()
        for candidate in matches {
            let resolved = candidate.hasPrefix("http") ? candidate : baseURL + candidate
            guard let url = URL(string: resolved) else { continue }
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count >= 2, parts[0] == "manga" else { continue }
            let slug = parts[1]
            if seen.insert(slug).inserted {
                slugs.append(slug)
            }
        }
        return slugs
    }

    private static func extractChapters(from html: String, mangaID: String, baseURL: String) -> [Chapter] {
        let pattern = "<a[^>]*href=[\"']([^\"']+)[\"'][^>]*>(.*?)</a>"
        let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex?.matches(in: html, range: range) ?? []

        let iso = ISO8601DateFormatter()
        let chapters: [Chapter] = matches.enumerated().compactMap { offset, match in
            guard
                let urlRange = Range(match.range(at: 1), in: html),
                let bodyRange = Range(match.range(at: 2), in: html)
            else {
                return nil
            }
            let href = String(html[urlRange])
            let body = String(html[bodyRange])
            guard body.contains("<time") else { return nil }

            let title = SourceEngineUtilities.firstMatch(in: body, pattern: "<span[^>]*>(.*?)</span>", options: [.dotMatchesLineSeparators, .caseInsensitive])
                .map(SourceEngineUtilities.stripHTML)
                .map(SourceEngineUtilities.decodeHTML) ?? "Chapter \(offset + 1)"
            let datetime = SourceEngineUtilities.firstMatch(in: body, pattern: "<time[^>]*datetime=[\"']([^\"']+)", options: [.dotMatchesLineSeparators, .caseInsensitive]) ?? ""
            let releaseDate = iso.date(from: datetime) ?? .now
            let absoluteURL = href.hasPrefix("http") ? href : baseURL + href

            return Chapter(
                id: absoluteURL,
                mangaID: mangaID,
                title: title,
                number: chapterNumber(from: title, fallback: offset),
                releaseDate: releaseDate,
                isDownloaded: false,
                pages: []
            )
        }

        return chapters.sorted { $0.number > $1.number }
    }

    private static func extractPageImageURLs(from html: String, baseURL: String) -> [String] {
        let pattern = "<img[^>]+src=[\"']([^\"']+)[\"']"
        let rawURLs = SourceEngineUtilities.allMatches(in: html, pattern: pattern)
            .map { $0.hasPrefix("http") ? $0 : baseURL + $0 }

        let primary = rawURLs.filter { isPrimaryReaderImageURL($0) }
        if !primary.isEmpty {
            return unique(primary)
        }

        let fallback = rawURLs.filter { isFallbackReaderImageURL($0) }
        if !fallback.isEmpty {
            return unique(fallback)
        }

        let grouped = Dictionary(grouping: rawURLs.filter { isLikelyPageImageURL($0) }, by: imageHostKey)
        if let best = grouped.values.max(by: { $0.count < $1.count }), best.count >= 3 {
            return unique(best)
        }

        return []
    }

    private static func isPrimaryReaderImageURL(_ url: String) -> Bool {
        (url.contains("yuucdn.com") && url.contains("/wp-content/uploads/images/")) ||
        (url.contains("cdn.uqni.net") && url.contains("/images/"))
    }

    private static func isFallbackReaderImageURL(_ url: String) -> Bool {
        isLikelyPageImageURL(url) &&
        !isBlockedReaderAssetURL(url) &&
        (url.contains("/chapter-") || url.contains("/Chapter%20") || url.contains("/chapter "))
    }

    private static func isLikelyPageImageURL(_ url: String) -> Bool {
        !isBlockedReaderAssetURL(url) &&
        (url.lowercased().hasSuffix(".webp") || url.lowercased().hasSuffix(".jpg") || url.lowercased().hasSuffix(".jpeg") || url.lowercased().hasSuffix(".png"))
    }

    private static func isBlockedReaderAssetURL(_ url: String) -> Bool {
        url.contains("blogger.googleusercontent.com") ||
        url.contains("images.envira-cdn.com") ||
        url.contains("secure.gravatar.com") ||
        url.localizedCaseInsensitiveContains("logo") ||
        url.localizedCaseInsensitiveContains("banner") ||
        url.localizedCaseInsensitiveContains("gif")
    }

    private static func detectBlockedImageHosts(in html: String) -> Bool {
        html.contains("blogger.googleusercontent.com") || html.contains("images.envira-cdn.com")
    }

    private static func imageHostKey(for url: String) -> String {
        URL(string: url)?.host ?? "unknown"
    }

    private static func unique(_ urls: [String]) -> [String] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0).inserted }
    }

    private static func extractOGImage(from yoastHead: String?) -> String? {
        guard let yoastHead else { return nil }
        return SourceEngineUtilities.firstMatch(in: yoastHead, pattern: "property=\\\"og:image\\\" content=\\\"([^\\\"]+)\\\"")
    }

    private static func chapterNumber(from title: String, fallback: Int) -> Double {
        let pattern = "(\\d+(?:\\.\\d+)?)"
        guard let value = SourceEngineUtilities.firstMatch(in: title, pattern: pattern), let number = Double(value) else {
            return Double(max(1, 10_000 - fallback))
        }
        return number
    }
}

// MARK: - NatsuId DTOs

struct GenreTermDTO: Decodable {
    let name: String
    let slug: String
}

struct NatsuMangaDTO: Decodable {
    let id: Int
    let slug: String
    let title: RenderedDTO
    let content: RenderedDTO
    let embedded: EmbeddedDTO
    let yoastHead: String?

    enum CodingKeys: String, CodingKey {
        case id
        case slug
        case title
        case content
        case embedded = "_embedded"
        case yoastHead = "yoast_head"
    }

    var isNovel: Bool {
        embedded.termGroups
            .flatMap { $0 }
            .filter { $0.taxonomy == "type" }
            .map(\.name)
            .contains("Novel")
    }
}

struct RenderedDTO: Decodable {
    let rendered: String
}

struct EmbeddedDTO: Decodable {
    let featuredMedia: [FeaturedMediaDTO]
    let termGroups: [[TermDTO]]

    enum CodingKeys: String, CodingKey {
        case featuredMedia = "wp:featuredmedia"
        case termGroups = "wp:term"
    }
}

struct FeaturedMediaDTO: Decodable {
    let sourceURL: String

    enum CodingKeys: String, CodingKey {
        case sourceURL = "source_url"
    }
}

struct TermDTO: Decodable {
    let name: String
    let slug: String
    let taxonomy: String
}
