//
//  RuntimeSourceRepository.swift
//  Mihon IOS
//

import Foundation

enum RuntimeSourceError: LocalizedError {
    case unsupportedSource
    case invalidResponse
    case nonceMissing
    case mangaNotFound
    case chapterPagesMissing
    case parserEmpty
    case blockedImageHost
    case unsupportedChapterMarkup

    var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            return "This source does not provide a runtime implementation."
        case .invalidResponse:
            return "The source returned data in an unexpected format."
        case .nonceMissing:
            return "Unable to fetch the source search nonce."
        case .mangaNotFound:
            return "Unable to resolve the requested manga."
        case .chapterPagesMissing:
            return "Unable to resolve chapter pages from the source."
        case .parserEmpty:
            return "The chapter loaded, but no readable manga pages were found."
        case .blockedImageHost:
            return "The chapter pages are served from an unsupported image host."
        case .unsupportedChapterMarkup:
            return "This chapter uses markup the current Kiryuu parser does not understand yet."
        }
    }
}

actor SourceRateLimiter {
    private let minimumIntervalNanoseconds: UInt64
    private var lastFireTime: UInt64 = 0

    init(requestsPerSecond: Int) {
        let safeRate = max(requestsPerSecond, 1)
        self.minimumIntervalNanoseconds = UInt64(1_000_000_000 / safeRate)
    }

    func waitTurn() async {
        let now = DispatchTime.now().uptimeNanoseconds
        if lastFireTime > 0, now < lastFireTime + minimumIntervalNanoseconds {
            let delay = (lastFireTime + minimumIntervalNanoseconds) - now
            try? await Task.sleep(nanoseconds: delay)
        }
        lastFireTime = DispatchTime.now().uptimeNanoseconds
    }
}

final class NatsuIdSourceEngine: SourceRuntime {
    let source: Source

    private let configuration: NatsuIdSourceConfiguration
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let rateLimiter: SourceRateLimiter
    private var nonceCache: String?
    private var genreCache: [GenreTag] = []

    private static let defaultUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1 Mihon-iOS/1.0"

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
            "User-Agent": Self.defaultUserAgent,
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
                accentHex: Self.paletteColor(seed: "\(chapter.id)-\(index)"),
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
        let tags = terms.map { GenreTag(name: Self.decodeHTML($0.name), slug: $0.slug) }
        genreCache = tags
        return tags
    }

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
        request.setValue(Self.defaultUserAgent, forHTTPHeaderField: "User-Agent")
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
                    // Cloudflare and similar can respond with 403/503; retry briefly
                    if attempt < maxAttempts && (status == 403 || status == 429 || status == 503) {
                        try? await Task.sleep(nanoseconds: 700_000_000) // 0.7s backoff
                        continue
                    }
                    throw RuntimeSourceError.invalidResponse
                }
                return data
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s backoff
                    continue
                }
            }
        }
        throw lastError ?? RuntimeSourceError.invalidResponse
    }

    private func mapManga(_ entry: NatsuMangaDTO, appendIdentifier: Bool) -> Manga {
        let terms = entry.embedded.termGroups.flatMap { $0 }
        let author = terms.filter { $0.taxonomy == "series-author" }.map { Self.decodeHTML($0.name) }.joined(separator: ", ")
        let artist = terms.filter { $0.taxonomy == "artist" }.map { Self.decodeHTML($0.name) }.joined(separator: ", ")
        let genres = Array(Set(
            terms
                .filter { $0.taxonomy == "genre" || $0.taxonomy == "type" }
                .map { Self.decodeHTML($0.name) }
        )).sorted()
        let statusTerms = terms.filter { $0.taxonomy == "status" }.map { Self.decodeHTML($0.name) }
        let summaryBody = Self.stripHTML(entry.content.rendered)
        let summary = appendIdentifier ? "\(summaryBody)\n\nID: \(entry.id)" : summaryBody
        let authorLine = [author, artist].filter { !$0.isEmpty }.joined(separator: " • ")

        return Manga(
            id: "\(source.id)::\(entry.id)::\(entry.slug)",
            sourceID: source.id,
            title: Self.decodeHTML(entry.title.rendered),
            author: authorLine.isEmpty ? "Unknown" : authorLine,
            summary: summary,
            genres: genres,
            coverHexes: Self.palette(for: entry.slug),
            coverURL: entry.embedded.featuredMedia.first?.sourceURL ?? Self.extractOGImage(from: entry.yoastHead),
            statusText: statusTerms.first ?? "Unknown"
        )
    }

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
        return firstMatch(in: html, pattern: pattern)
    }

    private static func extractSlugs(from html: String, baseURL: String) -> [String] {
        let pattern = "href=[\"']([^\"']+/manga/[^\"']+)[\"']"
        let matches = allMatches(in: html, pattern: pattern)
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

            let title = firstMatch(in: body, pattern: "<span[^>]*>(.*?)</span>", options: [.dotMatchesLineSeparators, .caseInsensitive])
                .map(stripHTML)
                .map(decodeHTML) ?? "Chapter \(offset + 1)"
            let datetime = firstMatch(in: body, pattern: "<time[^>]*datetime=[\"']([^\"']+)", options: [.dotMatchesLineSeparators, .caseInsensitive]) ?? ""
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
        let rawURLs = allMatches(in: html, pattern: pattern)
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

    private static func stripHTML(_ html: String) -> String {
        let withoutTags = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return decodeHTML(withoutTags)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private static func extractOGImage(from yoastHead: String?) -> String? {
        guard let yoastHead else { return nil }
        return firstMatch(in: yoastHead, pattern: "property=\\\"og:image\\\" content=\\\"([^\\\"]+)\\\"")
    }

    private static func palette(for seed: String) -> [String] {
        let palette: [[String]] = [
            ["#F97316", "#431407"],
            ["#2563EB", "#172554"],
            ["#16A34A", "#052E16"],
            ["#7C3AED", "#2E1065"],
            ["#DC2626", "#450A0A"],
        ]
        let value = abs(seed.hashValue) % palette.count
        return palette[value]
    }

    private static func paletteColor(seed: String) -> String {
        palette(for: seed).first ?? "#2563EB"
    }

    private static func chapterNumber(from title: String, fallback: Int) -> Double {
        let pattern = "(\\d+(?:\\.\\d+)?)"
        guard let value = firstMatch(in: title, pattern: pattern), let number = Double(value) else {
            return Double(max(1, 10_000 - fallback))
        }
        return number
    }

    private static func firstMatch(in text: String, pattern: String, options: NSRegularExpression.Options = []) -> String? {
        let regex = try? NSRegularExpression(pattern: pattern, options: options)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex?.firstMatch(in: text, range: range),
            let capture = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[capture])
    }

    private static func allMatches(in text: String, pattern: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> [String] {
        let regex = try? NSRegularExpression(pattern: pattern, options: options)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex?.matches(in: text, range: range) ?? []
        return matches.compactMap { match in
            guard let capture = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[capture])
        }
    }
}

final class AsuraAPISourceEngine: SourceRuntime {
    let source: Source
    private let baseURL: String
    private let apiBaseURL: String
    private let session: URLSession
    private let rateLimiter = SourceRateLimiter(requestsPerSecond: 4)

    // MARK: - Debug logging (only in DEBUG builds)
    private func debugLog(_ items: @autoclosure () -> String) {
#if DEBUG
        print("[AsuraAPI] \(items())")
#endif
    }

    init(source: Source, baseURL: String, apiBaseURL: String = "https://gg.asuracomic.net") {
        self.source = source
        self.baseURL = baseURL
        self.apiBaseURL = apiBaseURL
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1 Mihon-iOS/1.0",
            "Accept-Language": "en-US,en;q=0.9",
            "Accept": "application/json, text/html;q=0.1,*/*;q=0.1",
            "Referer": baseURL + "/"
        ]
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API (scaffolded)
    func popularManga(page: Int) async throws -> [Manga] {
        // Placeholder: fall back to HTML listing for now
        let htmlURL = URL(string: baseURL + "/series?genres=&status=-1&types=-1&order=rating&page=\(page)")!
        let html = try await getHTML(url: htmlURL)
        return AsuraHTMLSourceEngine.mapSeriesList(html: html, sourceID: source.id)
    }

    func latestManga(page: Int) async throws -> [Manga] {
        // Placeholder: fall back to HTML listing for now
        let htmlURL = URL(string: baseURL + "/page/\(page)")!
        let html = try await getHTML(url: htmlURL)
        return AsuraHTMLSourceEngine.mapSeriesList(html: html, sourceID: source.id)
    }

    func searchManga(_ request: SourceSearchRequest) async throws -> [Manga] {
        // Placeholder: fall back to HTML listing for now
        var components = URLComponents(string: baseURL + "/series")!
        components.queryItems = [URLQueryItem(name: "page", value: String(request.page))]
        let q = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { components.queryItems?.append(URLQueryItem(name: "name", value: q)) }
        let html = try await getHTML(url: components.url!)
        return AsuraHTMLSourceEngine.mapSeriesList(html: html, sourceID: source.id)
    }

    func mangaDetails(mangaIDOrURL: String) async throws -> SourceMangaDetails {
        let slug = Self.slug(from: mangaIDOrURL)
        debugLog("mangaDetails for slug: \(slug)")
        
        // Fetch the series page HTML
        let seriesURL = URL(string: baseURL + "/series/\(slug)")!
        debugLog("Fetching series page: \(seriesURL.absoluteString)")
        let html = try await getHTML(url: seriesURL)
        
        debugLog("HTML length: \(html.count) characters")
        
        // Try to find Next.js data in different formats
        // 1. Try __NEXT_DATA__
        let nextDataPattern = "<script id=\"__NEXT_DATA__\" type=\"application/json\">([\\s\\S]*?)</script>"
        if let nextDataJSON = Self.firstMatch(in: html, pattern: nextDataPattern, options: [.dotMatchesLineSeparators]) {
            debugLog("✅ Found __NEXT_DATA__, attempting to parse")
            return try await parseFromNextData(html: html, slug: slug, nextDataJSON: nextDataJSON)
        }
        
        // 2. Try to find embedded JSON in script tags
        debugLog("⚠️ No __NEXT_DATA__ found, trying alternative script tags...")
        let scriptPattern = "<script[^>]*>([\\s\\S]*?)</script>"
        let allScripts = Self.allMatches(in: html, pattern: scriptPattern, options: [.dotMatchesLineSeparators])
        debugLog("Found \(allScripts.count) script tags")
        
        for (index, script) in allScripts.enumerated() {
            if script.contains("\"series\"") && script.contains("\"title\"") {
                debugLog("Found potential series data in script tag #\(index)")
                debugLog("Script preview: \(script.prefix(200))...")
                // This might be inline data
                break
            }
        }
        
        // 3. Fall back to HTML scraping
        debugLog("⚠️ Falling back to HTML scraping")
        return try parseFromHTML(html: html, slug: slug)
    }
    
    private func parseFromNextData(html: String, slug: String, nextDataJSON: String) async throws -> SourceMangaDetails {
        guard let jsonData = nextDataJSON.data(using: .utf8) else {
            debugLog("❌ Failed to convert JSON string to Data")
            throw RuntimeSourceError.invalidResponse
        }
        
        // Decode Next.js page props
        struct NextData: Decodable {
            let props: PageProps
            
            struct PageProps: Decodable {
                let pageProps: SeriesPageProps
            }
            
            struct SeriesPageProps: Decodable {
                let series: SeriesDTO?
            }
            
            struct SeriesDTO: Decodable {
                let title: String?
                let slug: String?
                let description: String?
                let thumbnail: String?
                let status: String?
                let author: String?
                let artist: String?
                let genres: [GenreDTO]?
                
                struct GenreDTO: Decodable {
                    let name: String?
                }
            }
        }
        
        let decoder = JSONDecoder()
        let nextData: NextData
        do {
            nextData = try decoder.decode(NextData.self, from: jsonData)
            debugLog("✅ Successfully decoded NextData")
        } catch {
            debugLog("❌ Failed to decode NextData: \(error)")
            throw RuntimeSourceError.invalidResponse
        }
        
        guard let series = nextData.props.pageProps.series else {
            debugLog("❌ No series data in pageProps")
            throw RuntimeSourceError.mangaNotFound
        }
        
        let title = series.title ?? slug.replacingOccurrences(of: "-", with: " ").capitalized
        let description = series.description ?? "No description available."
        let coverURL = series.thumbnail
        let status = series.status ?? "Unknown"
        
        var authorParts: [String] = []
        if let author = series.author, !author.isEmpty {
            authorParts.append(author)
        }
        if let artist = series.artist, !artist.isEmpty, artist != series.author {
            authorParts.append(artist)
        }
        let authorLine = authorParts.isEmpty ? "Unknown" : authorParts.joined(separator: " • ")
        let genres = series.genres?.compactMap { $0.name }.filter { !$0.isEmpty } ?? ["Manhwa"]
        
        let manga = Manga(
            id: "\(source.id)::\(slug)",
            sourceID: source.id,
            title: title,
            author: authorLine,
            summary: Self.stripHTML(description),
            genres: genres,
            coverHexes: Self.palette(for: slug),
            coverURL: coverURL,
            statusText: status
        )
        
        return SourceMangaDetails(manga: manga)
    }
    
    private func parseFromHTML(html: String, slug: String) throws -> SourceMangaDetails {
        debugLog("Parsing manga details from HTML...")
        
        // Extract title
        var title = slug.replacingOccurrences(of: "-", with: " ").capitalized
        if let h1 = Self.firstMatch(in: html, pattern: "<h1[^>]*>([^<]+)</h1>", options: [.dotMatchesLineSeparators, .caseInsensitive]) {
            title = Self.stripHTML(h1)
            debugLog("Found title: \(title)")
        }
        
        // Extract cover image
        var coverURL: String?
        if let imgSrc = Self.firstMatch(in: html, pattern: "<img[^>]*alt=\"[^\"]*cover[^\"]*\"[^>]*src=\"([^\"]+)\"", options: [.caseInsensitive]) {
            coverURL = imgSrc
            debugLog("Found cover: \(imgSrc)")
        } else if let ogImage = Self.firstMatch(in: html, pattern: "property=\"og:image\"[^>]*content=\"([^\"]+)\"") {
            coverURL = ogImage
            debugLog("Found OG image: \(ogImage)")
        }
        
        // Extract description
        var description = "No description available."
        if let desc = Self.firstMatch(in: html, pattern: "<div[^>]*class=\"[^\"]*description[^\"]*\"[^>]*>([\\s\\S]{50,2000}?)</div>", options: [.dotMatchesLineSeparators, .caseInsensitive]) {
            description = Self.stripHTML(desc)
            debugLog("Found description: \(description.prefix(100))...")
        }
        
        let manga = Manga(
            id: "\(source.id)::\(slug)",
            sourceID: source.id,
            title: title,
            author: "Unknown",
            summary: description,
            genres: ["Manhwa"],
            coverHexes: Self.palette(for: slug),
            coverURL: coverURL,
            statusText: "Unknown"
        )
        
        debugLog("✅ Manga created from HTML: \(manga.title)")
        return SourceMangaDetails(manga: manga)
    }

    func chapters(for manga: Manga) async throws -> SourceChapterDetails {
        let slug = Self.slug(from: manga.id)
        debugLog("chapters() for manga: \(manga.title), slug: \(slug)")
        
        // First, try using the API directly (asuracomic often has a chapters API)
        do {
            debugLog("Trying API endpoint for chapters...")
            let apiURL = URL(string: "\(apiBaseURL)/api/series/\(slug)/chapters")!
            let (data, response) = try await session.data(from: apiURL)
            
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                debugLog("✅ Got response from chapters API")
                
                // Try to decode chapters from API
                struct ChaptersResponse: Decodable {
                    let data: [ChapterDTO]?
                    let chapters: [ChapterDTO]?
                }
                
                struct ChapterDTO: Decodable {
                    let id: String?
                    let name: String?
                    let slug: String?
                    let number: String?
                    let created_at: String?
                }
                
                let decoder = JSONDecoder()
                if let chaptersResponse = try? decoder.decode(ChaptersResponse.self, from: data) {
                    let chapterDTOs = chaptersResponse.data ?? chaptersResponse.chapters ?? []
                    debugLog("✅ Decoded \(chapterDTOs.count) chapters from API")
                    
                    if !chapterDTOs.isEmpty {
                        let iso = ISO8601DateFormatter()
                        let chapters: [Chapter] = chapterDTOs.enumerated().compactMap { index, dto in
                            guard let chapterSlug = dto.slug else { return nil }
                            
                            let title = dto.name ?? "Chapter \(dto.number ?? "\(index + 1)")"
                            let chapterNumber = Double(dto.number ?? "\(index + 1)") ?? Double(index + 1)
                            let releaseDate = dto.created_at.flatMap { iso.date(from: $0) } ?? .now
                            let chapterURL = "\(baseURL)/series/\(slug)/chapter/\(chapterSlug)"
                            
                            return Chapter(
                                id: chapterURL,
                                mangaID: manga.id,
                                title: title,
                                number: chapterNumber,
                                releaseDate: releaseDate,
                                isDownloaded: false,
                                pages: []
                            )
                        }
                        
                        let sortedChapters = chapters.sorted { $0.number > $1.number }
                        return SourceChapterDetails(chapters: sortedChapters)
                    }
                }
            }
        } catch {
            debugLog("⚠️ API request failed: \(error), falling back to HTML")
        }
        
        // Fall back to HTML scraping
        let seriesURL = URL(string: baseURL + "/series/\(slug)")!
        let html = try await getHTML(url: seriesURL)
        
        debugLog("HTML length: \(html.count) characters")
        
        // Try to extract chapter data from __NEXT_DATA__ (same approach as mangaDetails)
        debugLog("Attempting to extract chapters from __NEXT_DATA__...")
        let nextDataPattern = "<script id=\"__NEXT_DATA__\" type=\"application/json\">([\\s\\S]*?)</script>"
        if let nextDataJSON = Self.firstMatch(in: html, pattern: nextDataPattern, options: [.dotMatchesLineSeparators]) {
            debugLog("✅ Found __NEXT_DATA__ in series page")
            
            do {
                let chapters = try parseChaptersFromNextData(nextDataJSON: nextDataJSON, slug: slug, mangaID: manga.id)
                if !chapters.isEmpty {
                    debugLog("✅ Successfully extracted \(chapters.count) chapters from __NEXT_DATA__")
                    return SourceChapterDetails(chapters: chapters)
                } else {
                    debugLog("⚠️ __NEXT_DATA__ found but no chapters extracted")
                }
            } catch {
                debugLog("⚠️ Failed to parse __NEXT_DATA__: \(error)")
            }
        } else {
            debugLog("⚠️ No __NEXT_DATA__ found in series page")
        }
        
        // Save a snippet of HTML to inspect structure
        if html.count > 1000 {
            let snippet = String(html.prefix(2000))
            if snippet.lowercased().contains("chapter") {
                debugLog("HTML contains 'chapter' keyword - looking for structure...")
                // Look for chapter list container
                if let chapterListMatch = Self.firstMatch(in: snippet, pattern: "(<div[^>]*chapter[^>]*>.*)", options: [.caseInsensitive]) {
                    debugLog("Found chapter container: \(chapterListMatch.prefix(200))")
                }
            }
        }
        
        // Try multiple patterns for chapter links
        var matches: [[String]] = []
        
        // Pattern 1: /series/{slug}/chapter/{chapter-slug}
        debugLog("Trying pattern 1: /series/.../chapter/...")
        var chapterPattern = "<a[^>]*href=\"/series/[^/]+/chapter/([^\"]+)\"[^>]*>([\\s\\S]*?)</a>"
        matches = Self.allMatchesWithGroups(in: html, pattern: chapterPattern, groupCount: 2)
        debugLog("Pattern 1 found \(matches.count) matches")
        
        if matches.isEmpty {
            // Pattern 2: href="/series/{slug}/{chapter-slug}" (might not have /chapter/ prefix)
            debugLog("Trying pattern 2: /series/\(slug)/...")
            chapterPattern = "href=\"/series/\(slug.replacingOccurrences(of: "-", with: "\\-"))/([^\"]+)\""
            matches = Self.allMatchesWithGroups(in: html, pattern: chapterPattern, groupCount: 1)
            debugLog("Pattern 2 found \(matches.count) matches")
        }
        
        if matches.isEmpty {
            // Pattern 3: Look for any link containing "chapter" in the href
            debugLog("Trying pattern 3: any link with 'chapter'...")
            chapterPattern = "href=\"([^\"]*chapter[^\"]+)\""
            let chapterURLs = Self.allMatches(in: html, pattern: chapterPattern, options: [])
            debugLog("Pattern 3 found \(chapterURLs.count) potential chapter URLs")
            
            // Filter to only URLs that look like series chapter links
            let validChapterURLs = chapterURLs.filter { url in
                // Should contain the series slug and "chapter/"
                url.contains(slug) && url.contains("chapter/")
            }
            
            // Remove duplicates
            let uniqueURLs = Array(Set(validChapterURLs))
            
            if !uniqueURLs.isEmpty {
                debugLog("After filtering: \(uniqueURLs.count) unique chapter URLs")
                debugLog("Sample raw URLs: \(uniqueURLs.prefix(5).joined(separator: " | "))")
                
                // Log the actual format we'll use
                if let firstURL = uniqueURLs.first {
                    let testURL: String
                    if firstURL.hasPrefix("http") {
                        testURL = firstURL
                    } else if firstURL.hasPrefix("/") {
                        testURL = baseURL + firstURL
                    } else if firstURL.hasPrefix("series/") {
                        testURL = baseURL + "/" + firstURL
                    } else {
                        // Relative URL without /series/ prefix - need to add it
                        testURL = baseURL + "/series/" + firstURL
                    }
                    debugLog("First URL will be: \(testURL)")
                }
                
                // Convert to matches format
                matches = uniqueURLs.map { [$0] }
            }
        }
        
        if matches.isEmpty {
            // Pattern 4: Try finding data-* attributes or other Next.js patterns
            debugLog("Trying pattern 4: looking for data attributes...")
            let dataPattern = "data-chapter[^>]*=\\\"([^\\\"]+)\\\""
            let dataChapters = Self.allMatches(in: html, pattern: dataPattern, options: [])
            debugLog("Found \(dataChapters.count) data-chapter attributes")
        }
        
        debugLog("Final match count: \(matches.count)")
        
        var chapters: [Chapter] = []
        for (index, groups) in matches.enumerated() {
            guard !groups.isEmpty else { continue }
            let rawURL = groups[0]
            let linkHTML = groups.count > 1 ? groups[1] : ""
            
            // Build the full URL
            let chapterURL: String
            if rawURL.hasPrefix("http") {
                // Absolute URL
                chapterURL = rawURL
            } else if rawURL.hasPrefix("/") {
                // Root-relative URL like "/series/slug/chapter/123"
                chapterURL = baseURL + rawURL
            } else if rawURL.hasPrefix("series/") {
                // Relative URL starting with "series/"
                chapterURL = baseURL + "/" + rawURL
            } else {
                // Relative URL like "slug/chapter/123" - needs /series/ prefix
                chapterURL = baseURL + "/series/" + rawURL
            }
            
            // Extract chapter number from the URL path
            // Expected format: .../series/{slug}/chapter/{number}
            let numberPattern = "/chapter/(\\d+(?:\\.\\d+)?)"
            let chapterNumber: Double
            
            if let numStr = Self.firstMatch(in: chapterURL, pattern: numberPattern),
               let num = Double(numStr) {
                chapterNumber = num
            } else if !linkHTML.isEmpty,
                      let numStr = Self.firstMatch(in: linkHTML, pattern: "(\\d+(?:\\.\\d+)?)"),
                      let num = Double(numStr) {
                chapterNumber = num
            } else {
                // Fallback to index
                chapterNumber = Double(index + 1)
            }
            
            let title = "Chapter \(chapterNumber)"
            
            let chapter = Chapter(
                id: chapterURL,
                mangaID: manga.id,
                title: title,
                number: chapterNumber,
                releaseDate: .now,
                isDownloaded: false,
                pages: []
            )
            chapters.append(chapter)
            if index < 3 {
                debugLog("  Chapter \(Int(chapterNumber)): \(chapterURL)")
            }
        }
        
        let sortedChapters = chapters.sorted { $0.number > $1.number }
        debugLog("✅ Returning \(sortedChapters.count) chapters from HTML")
        return SourceChapterDetails(chapters: sortedChapters)
    }
    
    // MARK: - Helper for parsing chapters from __NEXT_DATA__
    
    private func parseChaptersFromNextData(nextDataJSON: String, slug: String, mangaID: String) throws -> [Chapter] {
        guard let jsonData = nextDataJSON.data(using: .utf8) else {
            throw RuntimeSourceError.invalidResponse
        }
        
        // Define flexible decodable structures to handle different Next.js page structures
        struct NextData: Decodable {
            let props: PageProps
            
            struct PageProps: Decodable {
                let pageProps: SeriesPageProps
            }
            
            struct SeriesPageProps: Decodable {
                let chapters: [ChapterDTO]?
                let series: SeriesData?
                
                struct SeriesData: Decodable {
                    let chapters: [ChapterDTO]?
                }
            }
            
            struct ChapterDTO: Decodable {
                let id: String?
                let name: String?
                let slug: String?
                let number: String?
                let created_at: String?
                let createdAt: String?
                let published_at: String?
                let publishedAt: String?
                
                enum CodingKeys: String, CodingKey {
                    case id, name, slug, number
                    case created_at
                    case createdAt = "createdAt"
                    case published_at
                    case publishedAt = "publishedAt"
                }
            }
        }
        
        let decoder = JSONDecoder()
        let nextData = try decoder.decode(NextData.self, from: jsonData)
        
        // Try to find chapters in multiple locations
        let chapterDTOs = nextData.props.pageProps.chapters 
            ?? nextData.props.pageProps.series?.chapters 
            ?? []
        
        guard !chapterDTOs.isEmpty else {
            return []
        }
        
        let iso = ISO8601DateFormatter()
        let chapters: [Chapter] = chapterDTOs.enumerated().compactMap { index, dto in
            guard let chapterSlug = dto.slug else { return nil }
            
            let title = dto.name ?? "Chapter \(dto.number ?? "\(index + 1)")"
            let chapterNumber = Double(dto.number ?? "\(index + 1)") ?? Double(index + 1)
            
            // Try multiple date fields
            let dateString = dto.created_at ?? dto.createdAt ?? dto.published_at ?? dto.publishedAt
            let releaseDate = dateString.flatMap { iso.date(from: $0) } ?? .now
            
            let chapterURL = "\(baseURL)/series/\(slug)/chapter/\(chapterSlug)"
            
            return Chapter(
                id: chapterURL,
                mangaID: mangaID,
                title: title,
                number: chapterNumber,
                releaseDate: releaseDate,
                isDownloaded: false,
                pages: []
            )
        }
        
        return chapters.sorted { $0.number > $1.number }
    }

    func pages(for chapter: Chapter) async throws -> SourcePageAsset {
        guard let url = URL(string: chapter.id) else {
            debugLog("❌ Invalid chapter URL: \(chapter.id)")
            throw RuntimeSourceError.chapterPagesMissing
        }
        
        debugLog("pages() for chapter: \(chapter.title)")
        debugLog("Chapter URL: \(url.absoluteString)")
        
        // Fetch chapter page HTML
        do {
            await rateLimiter.waitTurn()
            let (data, response) = try await session.data(from: url)
            
            guard let http = response as? HTTPURLResponse else {
                debugLog("❌ No HTTPURLResponse")
                throw RuntimeSourceError.invalidResponse
            }
            
            debugLog("HTTP status: \(http.statusCode)")
            
            guard (200..<300).contains(http.statusCode) else {
                debugLog("❌ Bad status code: \(http.statusCode)")
                throw RuntimeSourceError.invalidResponse
            }
            
            guard let html = String(data: data, encoding: .utf8) else {
                debugLog("❌ Could not decode HTML as UTF-8")
                throw RuntimeSourceError.invalidResponse
            }
            
            debugLog("HTML length: \(html.count) characters")
            
            // Asura is a Next.js RSC (React Server Components) site.
            // Chapter page images are NOT rendered as <img> tags in the
            // initial HTML — they live inside serialized RSC / JSON payloads
            // in <script> tags with the structure:
            //   "pages":[{"order":1,"url":"https://gg.asuracomic.net/storage/media/426051/conversions/00-optimized.webp"}, ...]
            
            debugLog("Extracting chapter page URLs from RSC payload...")
            
            // Strategy 1: Find "pages":[...] array in the raw HTML/script data
            // Each entry has {"order":N,"url":"..."} — extract all "url" values
            // that sit inside a "pages":[ context.
            let pagesArrayPattern = #""pages"\s*:\s*\[(.*?)\]"#
            let pagesArrayMatches = Self.allMatches(
                in: html,
                pattern: pagesArrayPattern,
                options: [.dotMatchesLineSeparators]
            )
            debugLog("Found \(pagesArrayMatches.count) 'pages' arrays in payload")
            
            // From each pages array, pull out all url values
            var bestPages: [(order: Int, url: String)] = []
            for pagesContent in pagesArrayMatches {
                // Extract {"order":N,"url":"..."} entries
                let entryPattern = #""order"\s*:\s*(\d+)\s*,\s*"url"\s*:\s*"([^"]+)""#
                let entryRegex = try? NSRegularExpression(pattern: entryPattern, options: [])
                let range = NSRange(pagesContent.startIndex..<pagesContent.endIndex, in: pagesContent)
                let entryMatches = entryRegex?.matches(in: pagesContent, range: range) ?? []
                
                var entries: [(order: Int, url: String)] = []
                for entry in entryMatches {
                    guard let orderRange = Range(entry.range(at: 1), in: pagesContent),
                          let urlRange = Range(entry.range(at: 2), in: pagesContent) else { continue }
                    let order = Int(pagesContent[orderRange]) ?? 0
                    let url = String(pagesContent[urlRange])
                    entries.append((order: order, url: url))
                }
                
                debugLog("  pages array with \(entries.count) entries")
                if entries.count > 0 {
                    debugLog("  sample: order=\(entries[0].order), url=\(entries[0].url)")
                }
                
                // Keep the array with the most entries (the actual chapter pages)
                if entries.count > bestPages.count {
                    bestPages = entries
                }
            }
            
            // Strategy 2: If no "pages":[...] found, try extracting all
            // storage/media URLs that look like chapter pages
            if bestPages.isEmpty {
                debugLog("No 'pages' array found, trying direct URL extraction...")
                let directPattern = #"https://gg\.asuracomic\.net/storage/media/\d+/conversions/\d+-optimized\.webp"#
                let directRegex = try? NSRegularExpression(pattern: directPattern, options: [])
                let htmlNSRange = NSRange(html.startIndex..<html.endIndex, in: html)
                let directMatches = directRegex?.matches(in: html, range: htmlNSRange) ?? []
                
                // Deduplicate while preserving order
                var seen = Set<String>()
                var urls: [String] = []
                for match in directMatches {
                    guard let range = Range(match.range, in: html) else { continue }
                    let url = String(html[range])
                    if seen.insert(url).inserted {
                        urls.append(url)
                    }
                }
                
                debugLog("Direct URL extraction: \(urls.count) unique URLs")
                if !urls.isEmpty {
                    bestPages = urls.enumerated().map { (order: $0.offset + 1, url: $0.element) }
                }
            }
            
            guard !bestPages.isEmpty else {
                debugLog("❌ No chapter page URLs found in HTML")
                throw RuntimeSourceError.parserEmpty
            }
            
            // Sort by order and build reader pages
            let sorted = bestPages.sorted { $0.order < $1.order }
            let pages = sorted.enumerated().map { index, entry in
                if index < 3 {
                    debugLog("  Page \(entry.order): \(entry.url)")
                }
                return ReaderPage(
                    id: "\(chapter.id)#page-\(index + 1)",
                    index: index,
                    title: "Page \(index + 1)",
                    body: "",
                    accentHex: Self.paletteColor(seed: "\(chapter.id)-\(index)"),
                    assetKind: .image,
                    assetPath: nil,
                    remoteURL: entry.url
                )
            }
            
            debugLog("✅ Returning \(pages.count) pages")
            return SourcePageAsset(pages: pages, errorMessage: nil)
            
        } catch let error as RuntimeSourceError {
            debugLog("❌ RuntimeSourceError: \(error)")
            throw error
        } catch {
            debugLog("❌ Unexpected error: \(error)")
            throw RuntimeSourceError.invalidResponse
        }
    }

    func genreTags() async throws -> [GenreTag] { [] }

    // MARK: - Cookie/XSRF helpers (scaffold)
    private func xsrfToken() async -> String? {
        // Look for XSRF token in cookies for apiBaseURL domain
        let cookieStorage = HTTPCookieStorage.shared
        let cookies = cookieStorage.cookies ?? []
        for cookie in cookies {
            if cookie.domain.contains(URL(string: apiBaseURL)?.host ?? "") && cookie.name.lowercased().contains("xsrf") {
                return cookie.value
            }
        }
        return nil
    }

    // MARK: - Networking utils
    private func getHTML(url: URL) async throws -> String {
        await rateLimiter.waitTurn()
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw RuntimeSourceError.invalidResponse }
        guard let html = String(data: data, encoding: .utf8) else { throw RuntimeSourceError.invalidResponse }
        return html
    }

    private func getJSON(path: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(string: apiBaseURL + path)!
        components.queryItems = queryItems
        var request = URLRequest(url: components.url!)
        request.setValue(baseURL + "/", forHTTPHeaderField: "Referer")
        if let xsrf = await xsrfToken() {
            request.setValue(xsrf, forHTTPHeaderField: "x-xsrf-token")
        }
        await rateLimiter.waitTurn()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw RuntimeSourceError.invalidResponse }
        return data
    }

    private static func slug(from idOrURL: String) -> String {
        if let url = URL(string: idOrURL), url.host != nil {
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.count >= 2, parts[0] == "series" { return parts[1] }
        }
        let parts = idOrURL.components(separatedBy: "::")
        return parts.last ?? idOrURL
    }

    // MARK: - Small regex helpers (scaffold)
    private static func firstMatch(in text: String, pattern: String, options: NSRegularExpression.Options = []) -> String? {
        let regex = try? NSRegularExpression(pattern: pattern, options: options)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex?.firstMatch(in: text, range: range), let capture = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[capture])
    }

    private static func allMatches(in text: String, pattern: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> [String] {
        let regex = try? NSRegularExpression(pattern: pattern, options: options)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex?.matches(in: text, range: range) ?? []
        return matches.compactMap { match in
            guard let capture = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[capture])
        }
    }

    private static func stripHTML(_ html: String) -> String {
        let withoutTags = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return withoutTags.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func palette(for seed: String) -> [String] {
        let palette: [[String]] = [
            ["#F97316", "#431407"],
            ["#2563EB", "#172554"],
            ["#16A34A", "#052E16"],
            ["#7C3AED", "#2E1065"],
            ["#DC2626", "#450A0A"],
        ]
        let value = abs(seed.hashValue) % palette.count
        return palette[value]
    }

    private static func paletteColor(seed: String) -> String {
        palette(for: seed).first ?? "#2563EB"
    }
    
    private static func allMatchesWithGroups(in text: String, pattern: String, groupCount: Int) -> [[String]] {
        let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex?.matches(in: text, range: range) ?? []
        
        return matches.compactMap { match in
            var groups: [String] = []
            for i in 1...groupCount {
                if let captureRange = Range(match.range(at: i), in: text) {
                    groups.append(String(text[captureRange]))
                }
            }
            return groups.count == groupCount ? groups : nil
        }
    }
}

final class AsuraHTMLSourceEngine: SourceRuntime {
    let source: Source
    private let baseURL: String
    private let session: URLSession
    private let rateLimiter = SourceRateLimiter(requestsPerSecond: 3)

    init(source: Source, baseURL: String) {
        self.source = source
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1 Mihon-iOS/1.0",
            "Accept-Language": "en-US,en;q=0.9",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Referer": baseURL + "/"
        ]
        self.session = URLSession(configuration: config)
    }

    func popularManga(page: Int) async throws -> [Manga] {
        let url = URL(string: baseURL + "/series?genres=&status=-1&types=-1&order=rating&page=\(page)")!
        let html = try await getHTML(url: url)
        return Self.mapSeriesList(html: html, sourceID: source.id)
    }

    func latestManga(page: Int) async throws -> [Manga] {
        let url = URL(string: baseURL + "/page/\(page)")!
        let html = try await getHTML(url: url)
        return Self.mapSeriesList(html: html, sourceID: source.id)
    }

    func searchManga(_ request: SourceSearchRequest) async throws -> [Manga] {
        var components = URLComponents(string: baseURL + "/series")!
        components.queryItems = [
            URLQueryItem(name: "page", value: String(request.page)),
        ]
        let q = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "name", value: q))
        }
        let html = try await getHTML(url: components.url!)
        return Self.mapSeriesList(html: html, sourceID: source.id)
    }

    func mangaDetails(mangaIDOrURL: String) async throws -> SourceMangaDetails {
        // For now, return a stub mapped from the slug
        let slug = Self.slug(from: mangaIDOrURL)
        let title = Self.titleFromSlug(slug)
        let manga = Manga(
            id: "\(source.id)::\(slug)",
            sourceID: source.id,
            title: title,
            author: "Unknown",
            summary: "Imported from Asura listing. Details parsing not yet implemented.",
            genres: ["Manhwa"],
            coverHexes: ["#2563EB", "#172554"],
            coverURL: nil,
            statusText: "Unknown"
        )
        return SourceMangaDetails(manga: manga)
    }

    func chapters(for manga: Manga) async throws -> SourceChapterDetails {
        // Not implemented yet for Asura; return empty
        return SourceChapterDetails(chapters: [])
    }

    func pages(for chapter: Chapter) async throws -> SourcePageAsset {
        // Not implemented yet for Asura; return empty
        return SourcePageAsset(pages: [], errorMessage: "Pages not implemented for this source yet.")
    }

    func genreTags() async throws -> [GenreTag] { [] }

    private func getHTML(url: URL) async throws -> String {
        await rateLimiter.waitTurn()
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw RuntimeSourceError.invalidResponse
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw RuntimeSourceError.invalidResponse
        }
        return html
    }

    static func mapSeriesList(html: String, sourceID: String) -> [Manga] {
        // Extract slugs from /series/<slug> links
        let pattern = "/series/([a-zA-Z0-9\\-]+)/"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex?.matches(in: html, range: range) ?? []
        var seen = Set<String>()
        var items: [Manga] = []
        for match in matches {
            guard let slugRange = Range(match.range(at: 1), in: html) else { continue }
            let slug = String(html[slugRange])
            if !seen.insert(slug).inserted { continue }
            let title = titleFromSlug(slug)
            let manga = Manga(
                id: "\(sourceID)::\(slug)",
                sourceID: sourceID,
                title: title,
                author: "Unknown",
                summary: "Imported from Asura listing.",
                genres: ["Manhwa"],
                coverHexes: palette(for: slug),
                coverURL: nil,
                statusText: "Unknown"
            )
            items.append(manga)
        }
        return items
    }

    private static func titleFromSlug(_ slug: String) -> String {
        slug.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private static func palette(for seed: String) -> [String] {
        let palette: [[String]] = [
            ["#F97316", "#431407"],
            ["#2563EB", "#172554"],
            ["#16A34A", "#052E16"],
            ["#7C3AED", "#2E1065"],
            ["#DC2626", "#450A0A"],
        ]
        let value = abs(seed.hashValue) % palette.count
        return palette[value]
    }

    private static func slug(from idOrURL: String) -> String {
        if let url = URL(string: idOrURL), url.host != nil {
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.count >= 2, parts[0] == "series" { return parts[1] }
        }
        let parts = idOrURL.components(separatedBy: "::")
        return parts.last ?? idOrURL
    }
}

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

private struct GenreTermDTO: Decodable {
    let name: String
    let slug: String
}

private struct NatsuMangaDTO: Decodable {
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

private struct RenderedDTO: Decodable {
    let rendered: String
}

private struct EmbeddedDTO: Decodable {
    let featuredMedia: [FeaturedMediaDTO]
    let termGroups: [[TermDTO]]

    enum CodingKeys: String, CodingKey {
        case featuredMedia = "wp:featuredmedia"
        case termGroups = "wp:term"
    }
}

private struct FeaturedMediaDTO: Decodable {
    let sourceURL: String

    enum CodingKeys: String, CodingKey {
        case sourceURL = "source_url"
    }
}

private struct TermDTO: Decodable {
    let name: String
    let slug: String
    let taxonomy: String
}

