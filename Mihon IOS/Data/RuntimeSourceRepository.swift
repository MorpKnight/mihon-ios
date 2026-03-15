//
//  RuntimeSourceRepository.swift
//  Mihon IOS
//

import Foundation

enum RuntimeSourceError: LocalizedError {
    case unsupportedSource
    case unsupportedFamily(SourceEngineFamily)
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
        case .unsupportedFamily(let family):
            return "The \(family.title) runtime is registered but not implemented yet."
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

protocol SourceEngine {
    var family: SourceEngineFamily { get }
    func makeRuntime(from descriptor: SourceDescriptor, source: Source) throws -> any SourceRuntime
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

    init(configuration: NatsuIdSourceConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.source = configuration.source
        self.session = session
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
        if let nonceCache, !nonceCache.isEmpty {
            return nonceCache
        }

        let url = URL(string: configuration.baseURL + "/wp-admin/admin-ajax.php?type=search_form&action=get_nonce")!
        let html = try await getHTML(url: url)
        guard let nonce = Self.extractNonce(from: html) else {
            throw RuntimeSourceError.nonceMissing
        }
        nonceCache = nonce
        return nonce
    }

    private func postAdvancedSearch(request: SourceSearchRequest, nonce: String) async throws -> String {
        let boundary = "MihonBoundary-\(UUID().uuidString)"
        var urlRequest = URLRequest(url: URL(string: configuration.baseURL + "/wp-admin/admin-ajax.php?action=advanced_search")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(configuration.baseURL + "/", forHTTPHeaderField: "Referer")

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
        let data = try await getData(url: url, contentType: nil)
        guard let html = String(data: data, encoding: .utf8) else {
            throw RuntimeSourceError.invalidResponse
        }
        return html
    }

    private func getData(url: URL, contentType: String?) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(configuration.baseURL + "/", forHTTPHeaderField: "Referer")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Accept")
        }
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        await rateLimiter.waitTurn()
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw RuntimeSourceError.invalidResponse
        }
        return data
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

    fileprivate static func palette(for seed: String) -> [String] {
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

    fileprivate static func paletteColor(seed: String) -> String {
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

struct UnsupportedFamilyRuntime: SourceRuntime {
    let source: Source
    let family: SourceEngineFamily

    func popularManga(page: Int) async throws -> [Manga] { throw RuntimeSourceError.unsupportedFamily(family) }
    func latestManga(page: Int) async throws -> [Manga] { throw RuntimeSourceError.unsupportedFamily(family) }
    func searchManga(_ request: SourceSearchRequest) async throws -> [Manga] { throw RuntimeSourceError.unsupportedFamily(family) }
    func mangaDetails(mangaIDOrURL: String) async throws -> SourceMangaDetails { throw RuntimeSourceError.unsupportedFamily(family) }
    func chapters(for manga: Manga) async throws -> SourceChapterDetails { throw RuntimeSourceError.unsupportedFamily(family) }
    func pages(for chapter: Chapter) async throws -> SourcePageAsset { throw RuntimeSourceError.unsupportedFamily(family) }
    func genreTags() async throws -> [GenreTag] { throw RuntimeSourceError.unsupportedFamily(family) }
}

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

    private func parseMangaDetails(html: String, url: URL) throws -> Manga {
        let title = firstMatch(in: html, pattern: "<(?:h1|h3)[^>]*>([^<]+)</(?:h1|h3)>")?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title, !title.isEmpty else { throw RuntimeSourceError.mangaNotFound }

        let author = allMatches(in: html, pattern: "div class=[\"'](?:author-content|manga-authors)[^\"']*[\"'][\\s\\S]*?<a[^>]*>([^<]+)</a>", options: [.caseInsensitive]).map(decodeHTML).joined(separator: ", ")
        let artist = allMatches(in: html, pattern: "div class=[\"']artist-content[^\"']*[\"'][\\s\\S]*?<a[^>]*>([^<]+)</a>", options: [.caseInsensitive]).map(decodeHTML).joined(separator: ", ")
        let status = firstMatch(in: html, pattern: "summary-heading[^>]*>\\s*Status\\s*<[^>]+>\\s*<div[^>]*>\\s*<div[^>]*class=[\"']summary-content[\"'][^>]*>([^<]+)")
            ?? firstMatch(in: html, pattern: "post-status[^>]*>\\s*([^<]+)")
            ?? "Unknown"
        let description = firstMatch(in: html, pattern: "description-summary[\\s\\S]*?summary__content[^>]*>([\\s\\S]*?)</div>", options: [.caseInsensitive])
            ?? firstMatch(in: html, pattern: "manga-excerpt[^>]*>([\\s\\S]*?)</div>", options: [.caseInsensitive])
            ?? ""
        let genres = allMatches(in: html, pattern: "genres-content[\\s\\S]*?<a[^>]*>([^<]+)</a>", options: [.caseInsensitive]).map(decodeHTML)
        let thumbnail = firstImageURL(in: html)
        let slug = slugFromURLString(url.absoluteString)
        let people = [author, artist].filter { !$0.isEmpty }.joined(separator: " • ")

        return Manga(
            id: "\(source.id)::\(slug)",
            sourceID: source.id,
            title: decodeHTML(title),
            author: people.isEmpty ? "Unknown" : people,
            summary: stripHTML(description),
            genres: Array(Set(genres)).sorted(),
            coverHexes: NatsuIdSourceEngine.palette(for: slug),
            coverURL: thumbnail,
            statusText: decodeHTML(status)
        )
    }

    private func parseChapters(from html: String, mangaID: String) -> [Chapter] {
        let items = allMatches(in: html, pattern: "(<li[^>]*class=[\"'][^\"']*wp-manga-chapter[^\"']*[\"'][\\s\\S]*?</li>)", options: [.caseInsensitive])
        return items.enumerated().compactMap { offset, item in
            guard let href = firstMatch(in: item, pattern: "href=[\"']([^\"']+)[\"']") else { return nil }
            let title = firstMatch(in: item, pattern: "<a[^>]*href=[\"'][^\"']+[\"'][^>]*>([\\s\\S]*?)</a>", options: [.caseInsensitive]).map(stripHTML)
            let chapterURL = normalizedChapterURL(absolutize(href))
            let dateText = firstMatch(in: item, pattern: "chapter-release-date[^>]*>([^<]+)</", options: [.caseInsensitive])
                ?? firstMatch(in: item, pattern: "title=[\"']([^\"']+)[\"']", options: [.caseInsensitive])
            return Chapter(
                id: chapterURL,
                mangaID: mangaID,
                title: decodeHTML(title ?? "Chapter \(offset + 1)"),
                number: chapterNumber(from: title ?? "", fallback: offset),
                releaseDate: parseDate(dateText),
                isDownloaded: false,
                pages: []
            )
        }.sorted { $0.number > $1.number }
    }

    private func parsePageURLs(from html: String) -> [String] {
        let pageBreaks = allMatches(in: html, pattern: "<div[^>]*class=[\"'][^\"']*page-break[^\"']*[\"'][\\s\\S]*?</div>", options: [.caseInsensitive])
        let primary = pageBreaks.compactMap { firstImageURL(in: $0) }
        if !primary.isEmpty {
            return unique(primary)
        }
        let fallback = allMatches(in: html, pattern: "<img[^>]+(?:data-src|data-lazy-src|src|data-cfsrc)=[\"']([^\"']+)[\"']", options: [.caseInsensitive])
            .map(absolutize)
            .filter { !$0.localizedCaseInsensitiveContains("logo") && !$0.localizedCaseInsensitiveContains("banner") }
        return unique(fallback)
    }

    private func normalizedChapterURL(_ value: String) -> String {
        if value.contains("?style=list") {
            return value
        }
        if value.contains("?") {
            return value + "&style=list"
        }
        return value + "?style=list"
    }

    private func slugFromURLString(_ value: String) -> String {
        guard let url = URL(string: value) else { return value }
        return url.pathComponents.filter { $0 != "/" }.last ?? value
    }

    private func absolutize(_ value: String) -> String {
        if value.hasPrefix("http") { return value }
        let base = descriptor.context?.baseURL ?? ""
        if value.hasPrefix("/") {
            return base + value
        }
        return base + "/" + value
    }

    private func firstImageURL(in html: String) -> String? {
        firstMatch(in: html, pattern: "data-src=[\"']([^\"']+)[\"']", options: [.caseInsensitive]).map(absolutize)
            ?? firstMatch(in: html, pattern: "data-lazy-src=[\"']([^\"']+)[\"']", options: [.caseInsensitive]).map(absolutize)
            ?? firstMatch(in: html, pattern: "src=[\"']([^\"']+)[\"']", options: [.caseInsensitive]).map(absolutize)
    }

    private func parseDate(_ value: String?) -> Date {
        guard let value else { return .now }
        let cleaned = decodeHTML(value).trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = cleaned.lowercased()
        if lower.contains("today") {
            return .now
        }
        if lower.contains("yesterday") {
            return Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
        }
        if lower.contains("ago"), let count = Int(firstMatch(in: lower, pattern: "(\\d+)") ?? "0") {
            if lower.contains("day") { return Calendar.current.date(byAdding: .day, value: -count, to: .now) ?? .now }
            if lower.contains("hour") { return Calendar.current.date(byAdding: .hour, value: -count, to: .now) ?? .now }
            if lower.contains("min") { return Calendar.current.date(byAdding: .minute, value: -count, to: .now) ?? .now }
        }
        return dateFormatter.date(from: cleaned) ?? .now
    }

    private func getHTML(url: URL) async throws -> String {
        let data = try await getData(request: request(for: url))
        guard let html = String(data: data, encoding: .utf8) else {
            throw RuntimeSourceError.invalidResponse
        }
        return html
    }

    private func postHTML(url: URL, body: String?) async throws -> String? {
        var request = request(for: url)
        request.httpMethod = "POST"
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if let body {
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = body.data(using: .utf8)
        }
        let data = try await getData(request: request)
        return String(data: data, encoding: .utf8)
    }

    private func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if let referrer = descriptor.context?.requestPolicy.referrer {
            request.setValue(referrer, forHTTPHeaderField: "Referer")
        }
        if let userAgent = descriptor.context?.requestPolicy.userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        request.timeoutInterval = 20
        return request
    }

    private func getData(request: URLRequest) async throws -> Data {
        await rateLimiter.waitTurn()
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw RuntimeSourceError.invalidResponse
        }
        return data
    }

    private func firstMatch(in text: String, pattern: String, options: NSRegularExpression.Options = []) -> String? {
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

    private func allMatches(in text: String, pattern: String, options: NSRegularExpression.Options = []) -> [String] {
        let regex = try? NSRegularExpression(pattern: pattern, options: options)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return (regex?.matches(in: text, range: range) ?? []).compactMap { match in
            guard let capture = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[capture])
        }
    }

    private func allMatchPairs(in text: String, pattern: String, options: NSRegularExpression.Options = []) -> [(String, String)] {
        let regex = try? NSRegularExpression(pattern: pattern, options: options)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return (regex?.matches(in: text, range: range) ?? []).compactMap { match in
            guard
                let first = Range(match.range(at: 1), in: text),
                let second = Range(match.range(at: 2), in: text)
            else { return nil }
            return (String(text[first]), String(text[second]))
        }
    }

    private func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private func chapterNumber(from title: String, fallback: Int) -> Double {
        let pattern = "(\\d+(?:\\.\\d+)?)"
        guard let value = firstMatch(in: title, pattern: pattern), let number = Double(value) else {
            return Double(max(1, 10_000 - fallback))
        }
        return number
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

struct MadaraRuntimeFactory: SourceEngine {
    let family: SourceEngineFamily = .madara

    func makeRuntime(from descriptor: SourceDescriptor, source: Source) throws -> any SourceRuntime {
        guard descriptor.context != nil else {
            throw RuntimeSourceError.invalidResponse
        }
        return MadaraSourceEngine(source: source, descriptor: descriptor)
    }
}

final class MangaThemesiaSourceEngine: SourceRuntime {
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
        self.dateFormatter.dateFormat = descriptor.overrides["dateFormat"] ?? "MMMM dd, yyyy"
    }

    func popularManga(page: Int) async throws -> [Manga] {
        try await searchManga(SourceSearchRequest(query: "", page: page, filters: [.sort("popular")]))
    }

    func latestManga(page: Int) async throws -> [Manga] {
        try await searchManga(SourceSearchRequest(query: "", page: page, filters: [.sort("update")]))
    }

    func searchManga(_ request: SourceSearchRequest) async throws -> [Manga] {
        if let deepLink = deepLinkURL(from: request.query) {
            let html = try await getHTML(url: deepLink)
            let manga = try parseMangaDetails(html: html, url: deepLink)
            return [manga]
        }

        var queryItems = [
            URLQueryItem(name: "title", value: request.query),
            URLQueryItem(name: "page", value: String(max(request.page, 1))),
        ]

        for filter in request.filters {
            switch filter {
            case .sort(let value):
                if !value.isEmpty { queryItems.append(URLQueryItem(name: "order", value: value)) }
            case .types(let values):
                if let first = values.first { queryItems.append(URLQueryItem(name: "type", value: first.capitalized)) }
            case .genreInclude(_, let slugs):
                queryItems.append(contentsOf: slugs.map { URLQueryItem(name: "genre[]", value: $0) })
            default:
                break
            }
        }

        let url = searchURL(queryItems: queryItems)
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
        let chapters = parseChapters(from: html, mangaID: manga.id)
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
        let html = try await getHTML(url: searchURL(queryItems: [URLQueryItem(name: "title", value: "")]))
        let pairs = allMatchPairs(in: html, pattern: "<li[^>]*>\\s*<input[^>]*value=[\"']([^\"']+)[\"'][^>]*>\\s*<label[^>]*>([^<]+)</label>", options: [.caseInsensitive])
        return pairs.map { GenreTag(name: decodeHTML($0.1), slug: $0.0) }
    }

    private func searchURL(queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents(string: descriptor.context?.baseURL ?? "")!
        let path = descriptor.overrides["mangaSubPath"] ?? "manga"
        components.path = "/\(path)/"
        components.queryItems = queryItems
        return components.url!
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
        let path = descriptor.overrides["mangaSubPath"] ?? "manga"
        guard let url = URL(string: "\(descriptor.context?.baseURL ?? "")/\(path)/\(slug)/") else {
            throw RuntimeSourceError.mangaNotFound
        }
        return url
    }

    private func parseArchiveManga(from html: String) -> [Manga] {
        let blocks = allMatches(in: html, pattern: "(<(?:div)[^>]+(?:imgu|bsx)[\\s\\S]*?</(?:div)>)", options: [.caseInsensitive])
        var seen = Set<String>()
        return blocks.compactMap { block in
            guard
                let href = firstMatch(in: block, pattern: "href=[\"']([^\"']+)[\"']"),
                let title = firstMatch(in: block, pattern: "title=[\"']([^\"']+)[\"']")
                    ?? firstMatch(in: block, pattern: "<a[^>]*href=[\"'][^\"']+[\"'][^>]*>([^<]+)</a>")
            else { return nil }
            let slug = slugFromURLString(href)
            guard seen.insert(slug).inserted else { return nil }
            return Manga(
                id: "\(source.id)::\(slug)",
                sourceID: source.id,
                title: decodeHTML(title),
                author: "Unknown",
                summary: "MangaThemesia family source entry.",
                genres: [],
                coverHexes: NatsuIdSourceEngine.palette(for: slug),
                coverURL: firstImageURL(in: block),
                statusText: "Unknown"
            )
        }
    }

    private func parseMangaDetails(html: String, url: URL) throws -> Manga {
        let title = firstMatch(in: html, pattern: "<h1[^>]*class=[\"'][^\"']*entry-title[^\"']*[\"'][^>]*>([^<]+)</h1>", options: [.caseInsensitive])
            ?? firstMatch(in: html, pattern: "<span[^>]*>\\s*([^<]+)\\s*</span>\\s*</li>\\s*</ul>", options: [.caseInsensitive])
        guard let title, !title.isEmpty else { throw RuntimeSourceError.mangaNotFound }

        let author = firstMatch(in: html, pattern: "(?:Author|Pengarang|Yazar|Mangaka)[\\s\\S]*?<(?:i|span|td)[^>]*>([^<]+)</", options: [.caseInsensitive]) ?? ""
        let artist = firstMatch(in: html, pattern: "(?:artist|Artiste|Artista|İllüstratör|Çizer)[\\s\\S]*?<(?:i|span|td)[^>]*>([^<]+)</", options: [.caseInsensitive]) ?? ""
        let description = firstMatch(in: html, pattern: "<div[^>]*class=[\"'][^\"']*(?:desc|entry-content)[^\"']*[\"'][^>]*>([\\s\\S]*?)</div>", options: [.caseInsensitive]) ?? ""
        let thumbnail = firstImageURL(in: html)
        let genres = allMatches(in: html, pattern: "<a[^>]*class=[\"'][^\"']*(?:genre-tag)?[^\"']*[\"'][^>]*>([^<]+)</a>", options: [.caseInsensitive]).map(decodeHTML)
        let typeText = firstMatch(in: html, pattern: "(?:type|tipe|Türü)[\\s\\S]*?<a[^>]*>([^<]+)</a>", options: [.caseInsensitive])
        let status = firstMatch(in: html, pattern: "(?:status|Statut|Durum|Estado|الحالة)[\\s\\S]*?<[^>]+>([^<]+)</", options: [.caseInsensitive]) ?? "Unknown"
        let slug = slugFromURLString(url.absoluteString)
        let people = [author, artist].filter { !$0.isEmpty }.joined(separator: " • ")

        return Manga(
            id: "\(source.id)::\(slug)",
            sourceID: source.id,
            title: decodeHTML(title),
            author: people.isEmpty ? "Unknown" : people,
            summary: stripHTML(description),
            genres: Array(Set(genres + [typeText].compactMap { $0 })).map(decodeHTML).sorted(),
            coverHexes: NatsuIdSourceEngine.palette(for: slug),
            coverURL: thumbnail,
            statusText: decodeHTML(status)
        )
    }

    private func parseChapters(from html: String, mangaID: String) -> [Chapter] {
        let items = allMatches(in: html, pattern: "(<li[^>]*>(?=[\\s\\S]*?(?:chapternum|lch|chapterdate))[\\s\\S]*?</li>)", options: [.caseInsensitive])
        return items.enumerated().compactMap { offset, item in
            guard let href = firstMatch(in: item, pattern: "href=[\"']([^\"']+)[\"']") else { return nil }
            let title = firstMatch(in: item, pattern: "class=[\"'][^\"']*(?:lch|chapternum)[^\"']*[\"'][^>]*>([^<]+)</", options: [.caseInsensitive])
                ?? firstMatch(in: item, pattern: "<a[^>]*href=[\"'][^\"']+[\"'][^>]*>([^<]+)</a>")
            let dateText = firstMatch(in: item, pattern: "chapterdate[^>]*>([^<]+)</", options: [.caseInsensitive])
            return Chapter(
                id: absolutize(href),
                mangaID: mangaID,
                title: decodeHTML(title ?? "Chapter \(offset + 1)"),
                number: chapterNumber(from: title ?? "", fallback: offset),
                releaseDate: parseDate(dateText),
                isDownloaded: false,
                pages: []
            )
        }.sorted { $0.number > $1.number }
    }

    private func parsePageURLs(from html: String) -> [String] {
        let primary = allMatches(in: html, pattern: "<img[^>]+(?:data-lazy-src|data-src|data-cfsrc|src)=[\"']([^\"']+)[\"'][^>]*", options: [.caseInsensitive])
            .map(absolutize)
            .filter { !$0.localizedCaseInsensitiveContains("logo") && !$0.localizedCaseInsensitiveContains("avatar") }
        return unique(primary)
    }

    private func getHTML(url: URL) async throws -> String {
        let data = try await getData(request: request(for: url))
        guard let html = String(data: data, encoding: .utf8) else {
            throw RuntimeSourceError.invalidResponse
        }
        return html
    }

    private func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if let referrer = descriptor.context?.requestPolicy.referrer {
            request.setValue(referrer, forHTTPHeaderField: "Referer")
        }
        request.timeoutInterval = 20
        return request
    }

    private func getData(request: URLRequest) async throws -> Data {
        await rateLimiter.waitTurn()
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw RuntimeSourceError.invalidResponse
        }
        return data
    }

    private func slugFromURLString(_ value: String) -> String {
        guard let url = URL(string: absolutize(value)) else { return value }
        return url.pathComponents.filter { $0 != "/" }.last ?? value
    }

    private func absolutize(_ value: String) -> String {
        if value.hasPrefix("http") { return value }
        let base = descriptor.context?.baseURL ?? ""
        if value.hasPrefix("/") { return base + value }
        return base + "/" + value
    }

    private func firstImageURL(in html: String) -> String? {
        firstMatch(in: html, pattern: "data-lazy-src=[\"']([^\"']+)[\"']", options: [.caseInsensitive]).map(absolutize)
            ?? firstMatch(in: html, pattern: "data-src=[\"']([^\"']+)[\"']", options: [.caseInsensitive]).map(absolutize)
            ?? firstMatch(in: html, pattern: "src=[\"']([^\"']+)[\"']", options: [.caseInsensitive]).map(absolutize)
    }

    private func parseDate(_ value: String?) -> Date {
        guard let value else { return .now }
        return dateFormatter.date(from: decodeHTML(value).trimmingCharacters(in: .whitespacesAndNewlines)) ?? .now
    }

    private func firstMatch(in text: String, pattern: String, options: NSRegularExpression.Options = []) -> String? {
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

    private func allMatches(in text: String, pattern: String, options: NSRegularExpression.Options = []) -> [String] {
        let regex = try? NSRegularExpression(pattern: pattern, options: options)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return (regex?.matches(in: text, range: range) ?? []).compactMap { match in
            guard let capture = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[capture])
        }
    }

    private func allMatchPairs(in text: String, pattern: String, options: NSRegularExpression.Options = []) -> [(String, String)] {
        let regex = try? NSRegularExpression(pattern: pattern, options: options)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return (regex?.matches(in: text, range: range) ?? []).compactMap { match in
            guard
                let first = Range(match.range(at: 1), in: text),
                let second = Range(match.range(at: 2), in: text)
            else { return nil }
            return (String(text[first]), String(text[second]))
        }
    }

    private func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private func chapterNumber(from title: String, fallback: Int) -> Double {
        let pattern = "(\\d+(?:\\.\\d+)?)"
        guard let value = firstMatch(in: title, pattern: pattern), let number = Double(value) else {
            return Double(max(1, 10_000 - fallback))
        }
        return number
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

struct MangaThemesiaRuntimeFactory: SourceEngine {
    let family: SourceEngineFamily = .mangaThemesia

    func makeRuntime(from descriptor: SourceDescriptor, source: Source) throws -> any SourceRuntime {
        guard descriptor.context != nil else {
            throw RuntimeSourceError.invalidResponse
        }
        return MangaThemesiaSourceEngine(source: source, descriptor: descriptor)
    }
}

struct MangaBoxRuntimeFactory: SourceEngine {
    let family: SourceEngineFamily = .mangaBox

    func makeRuntime(from descriptor: SourceDescriptor, source: Source) throws -> any SourceRuntime {
        guard descriptor.context != nil else {
            throw RuntimeSourceError.invalidResponse
        }
        return MangaBoxSourceEngine(source: source, descriptor: descriptor)
    }
}

struct AsuraScansRuntimeFactory: SourceEngine {
    let family: SourceEngineFamily = .asuraScans

    func makeRuntime(from descriptor: SourceDescriptor, source: Source) throws -> any SourceRuntime {
        guard descriptor.context != nil else {
            throw RuntimeSourceError.invalidResponse
        }
        return AsuraScansSourceEngine(source: source, descriptor: descriptor)
    }
}

struct KomikIndoIDRuntimeFactory: SourceEngine {
    let family: SourceEngineFamily = .komikIndoID

    func makeRuntime(from descriptor: SourceDescriptor, source: Source) throws -> any SourceRuntime {
        guard descriptor.context != nil else {
            throw RuntimeSourceError.invalidResponse
        }
        return KomikIndoIDSourceEngine(source: source, descriptor: descriptor)
    }
}

struct NHentaiRuntimeFactory: SourceEngine {
    let family: SourceEngineFamily = .nhentai

    func makeRuntime(from descriptor: SourceDescriptor, source: Source) throws -> any SourceRuntime {
        guard descriptor.context != nil else {
            throw RuntimeSourceError.invalidResponse
        }
        return NHentaiSourceEngine(source: source, descriptor: descriptor)
    }
}

final class MangaBoxSourceEngine: SourceRuntime {
    let source: Source

    private let descriptor: SourceDescriptor
    private let session: URLSession
    private let rateLimiter: SourceRateLimiter
    private let dateFormatter: ISO8601DateFormatter

    init(source: Source, descriptor: SourceDescriptor, session: URLSession = .shared) {
        self.source = source
        self.descriptor = descriptor
        self.session = session
        self.rateLimiter = SourceRateLimiter(requestsPerSecond: max(descriptor.context?.requestPolicy.rateLimit ?? 2, 1))
        self.dateFormatter = ISO8601DateFormatter()
        self.dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func popularManga(page: Int) async throws -> [Manga] {
        try await parseArchive(url: rootURL(path: "/manga-list/hot-manga?page=\(page)"))
    }

    func latestManga(page: Int) async throws -> [Manga] {
        try await parseArchive(url: rootURL(path: "/manga-list/latest-manga?page=\(page)"))
    }

    func searchManga(_ request: SourceSearchRequest) async throws -> [Manga] {
        if !request.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let normalized = normalizeSearchQuery(request.query)
            return try await parseArchive(url: rootURL(path: "/search/story/\(normalized)?page=\(request.page)"))
        }

        var components = URLComponents(url: rootURL(path: "/genre"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "page", value: String(max(request.page, 1)))]
        for filter in request.filters {
            switch filter {
            case .sort(let value):
                components.queryItems?.append(URLQueryItem(name: "type", value: value))
            case .types(let values):
                if let first = values.first {
                    components.queryItems?.append(URLQueryItem(name: "state", value: first))
                }
            case .genreInclude(_, let slugs):
                if let first = slugs.first {
                    components.path += "/\(first)"
                }
            default:
                break
            }
        }
        return try await parseArchive(url: components.url!)
    }

    func mangaDetails(mangaIDOrURL: String) async throws -> SourceMangaDetails {
        let url = mangaURL(from: mangaIDOrURL)
        let html = try await getHTML(url: url)
        return SourceMangaDetails(manga: parseMangaDetails(html: html, url: url))
    }

    func chapters(for manga: Manga) async throws -> SourceChapterDetails {
        let slug = manga.id.components(separatedBy: "::").last ?? manga.id
        let url = rootURL(path: "/api/manga/\(slug)/chapters?limit=1000&offset=0")
        let data = try await getData(url: url, accept: "application/json")
        let response = try JSONDecoder().decode(MangaBoxAPIResponse.self, from: data)
        let chapters = response.data.chapters.map { chapter in
            Chapter(
                id: rootURL(path: "/manga/\(slug)/\(chapter.chapterSlug)").absoluteString,
                mangaID: manga.id,
                title: chapter.chapterName,
                number: Double(chapter.chapterNum),
                releaseDate: parseISODate(chapter.updatedAt),
                isDownloaded: false,
                pages: []
            )
        }.sorted { $0.number > $1.number }
        return SourceChapterDetails(chapters: chapters)
    }

    func pages(for chapter: Chapter) async throws -> SourcePageAsset {
        guard let url = URL(string: chapter.id) else { throw RuntimeSourceError.chapterPagesMissing }
        let html = try await getHTML(url: url)
        let scriptContent = allMatches(in: html, pattern: "cdns\\s*=\\s*\\[[^\\]]+]|backupImage\\s*=\\s*\\[[^\\]]+]|chapterImages\\s*=\\s*\\[[^\\]]+]", options: [.dotMatchesLineSeparators]).joined(separator: "\n")
        let cdns = extractArrayValues(from: scriptContent, name: "cdns") + extractArrayValues(from: scriptContent, name: "backupImage")
        let images = extractArrayValues(from: scriptContent, name: "chapterImages")
        let resolved = !cdns.isEmpty && !images.isEmpty
            ? images.enumerated().map { index, path in
                ReaderPage(id: "\(chapter.id)#\(index)", index: index, title: "Page \(index + 1)", body: "", accentHex: mangaColor(index), assetKind: .image, assetPath: nil, remoteURL: cdns[0].trimmingCharacters(in: .whitespacesAndNewlines) + "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            }
            : extractImagePages(from: html, chapterID: chapter.id)
        guard !resolved.isEmpty else { throw RuntimeSourceError.parserEmpty }
        return SourcePageAsset(pages: resolved, errorMessage: nil)
    }

    func genreTags() async throws -> [GenreTag] { [] }

    private func parseArchive(url: URL) async throws -> [Manga] {
        let html = try await getHTML(url: url)
        let hrefs = allMatches(in: html, pattern: "href=[\"']([^\"']+)[\"'][^>]*>\\s*<img[^>]+src=[\"']([^\"']+)[\"'][^>]*>.*?<h3[^>]*>\\s*<a[^>]*>(.*?)</a>")
        var mangas: [Manga] = []
        for chunk in hrefs {
            let matches = chunk.components(separatedBy: "\u{0}")
            _ = matches
        }
        let cardPattern = "<(?:div|a)[^>]*(?:list-truyen-item-wrap|list-comic-item-wrap|story_item)[^>]*>(.*?)</(?:div|a)>"
        let cards = allMatches(in: html, pattern: cardPattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
        mangas = cards.compactMap { card in
            guard
                let href = firstMatch(in: card, pattern: "href=[\"']([^\"']+)[\"']"),
                let title = firstMatch(in: card, pattern: "<h3[^>]*>\\s*<a[^>]*>(.*?)</a>", options: [.dotMatchesLineSeparators, .caseInsensitive]) ?? firstMatch(in: card, pattern: "title=[\"']([^\"']+)[\"']"),
                let thumb = firstMatch(in: card, pattern: "<img[^>]+src=[\"']([^\"']+)[\"']")
            else { return nil }
            return Manga(
                id: mangaID(from: href),
                sourceID: source.id,
                title: decodeHTML(stripHTML(title)),
                author: "Unknown",
                summary: "",
                genres: [],
                coverHexes: palette(for: href),
                coverURL: absoluteURL(href: thumb),
                statusText: "Unknown"
            )
        }
        return uniqueManga(mangas)
    }

    private func parseMangaDetails(html: String, url: URL) -> Manga {
        let title = firstMatch(in: html, pattern: "<h1[^>]*>(.*?)</h1>", options: [.dotMatchesLineSeparators, .caseInsensitive]) ??
            firstMatch(in: html, pattern: "<h2[^>]*>(.*?)</h2>", options: [.dotMatchesLineSeparators, .caseInsensitive]) ?? "Untitled"
        let author = allMatches(in: html, pattern: "(?:author|Author)</[^>]+>\\s*<[^>]+>(.*?)</a>", options: [.dotMatchesLineSeparators, .caseInsensitive]).map { decodeHTML(stripHTML($0)) }.joined(separator: ", ")
        let statusText = firstMatch(in: html, pattern: "(?:status|Status)</[^>]+>\\s*<[^>]+>(.*?)</", options: [.dotMatchesLineSeparators, .caseInsensitive]).map { decodeHTML(stripHTML($0)) } ?? "Unknown"
        let genres = allMatches(in: html, pattern: "(?:genres|Genres)</[^>]+>.*?</(?:li|td)>(.*?)</(?:li|td)>", options: [.dotMatchesLineSeparators, .caseInsensitive]).flatMap { chunk in
            allMatches(in: chunk, pattern: "<a[^>]*>(.*?)</a>", options: [.dotMatchesLineSeparators, .caseInsensitive]).map { decodeHTML(stripHTML($0)) }
        }
        let description = firstMatch(in: html, pattern: "<div[^>]*(?:noidungm|panel-story-info-description|contentBox)[^>]*>(.*?)</div>", options: [.dotMatchesLineSeparators, .caseInsensitive]).map(stripHTML) ?? ""
        let thumb = firstMatch(in: html, pattern: "<(?:img)[^>]+src=[\"']([^\"']+)[\"'][^>]*(?:manga-info-pic|info-image|cover)", options: [.dotMatchesLineSeparators, .caseInsensitive]) ??
            firstMatch(in: html, pattern: "<img[^>]+src=[\"']([^\"']+)[\"']")
        return Manga(
            id: mangaID(from: url.absoluteString),
            sourceID: source.id,
            title: decodeHTML(stripHTML(title)),
            author: author.isEmpty ? "Unknown" : author,
            summary: description,
            genres: genres,
            coverHexes: palette(for: url.absoluteString),
            coverURL: thumb.map(absoluteURL(href:)),
            statusText: statusText
        )
    }

    private func getHTML(url: URL) async throws -> String {
        let data = try await getData(url: url, accept: nil)
        guard let html = String(data: data, encoding: .utf8) else { throw RuntimeSourceError.invalidResponse }
        return html
    }

    private func getData(url: URL, accept: String?) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue((descriptor.baseURL ?? "") + "/", forHTTPHeaderField: "Referer")
        if let accept { request.setValue(accept, forHTTPHeaderField: "Accept") }
        await rateLimiter.waitTurn()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw RuntimeSourceError.invalidResponse
        }
        return data
    }

    private func rootURL(path: String) -> URL {
        URL(string: (descriptor.baseURL ?? "") + path)!
    }

    private func absoluteURL(href: String) -> String {
        if href.hasPrefix("http") { return href }
        return (descriptor.baseURL ?? "") + (href.hasPrefix("/") ? href : "/\(href)")
    }

    private func mangaURL(from value: String) -> URL {
        if let url = URL(string: value), url.scheme != nil { return url }
        let slug = value.components(separatedBy: "::").last ?? value
        return rootURL(path: "/manga/\(slug)")
    }

    private func mangaID(from href: String) -> String {
        let absolute = absoluteURL(href: href)
        return "\(source.id)::\(URL(string: absolute)?.lastPathComponent ?? absolute)"
    }

    private func parseISODate(_ value: String) -> Date {
        dateFormatter.date(from: value) ?? .now
    }

    private func normalizeSearchQuery(_ query: String) -> String {
        var value = query.lowercased()
        value = value.replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}

final class AsuraScansSourceEngine: SourceRuntime {
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
        self.dateFormatter.dateFormat = "MMMM d yyyy"
    }

    func popularManga(page: Int) async throws -> [Manga] {
        try await parseCards(url: rootURL(path: "/series?genres=&status=-1&types=-1&order=rating&page=\(page)"))
    }

    func latestManga(page: Int) async throws -> [Manga] {
        try await parseLatest(url: rootURL(path: "/page/\(page)"))
    }

    func searchManga(_ request: SourceSearchRequest) async throws -> [Manga] {
        var components = URLComponents(url: rootURL(path: "/series"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "page", value: String(max(request.page, 1)))]
        let trimmed = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { items.append(URLQueryItem(name: "name", value: trimmed)) }
        for filter in request.filters {
            switch filter {
            case .sort(let value):
                items.append(URLQueryItem(name: "order", value: value))
            case .types(let values):
                items.append(URLQueryItem(name: "types", value: values.joined(separator: ",")))
            case .genreInclude(_, let slugs):
                items.append(URLQueryItem(name: "genres", value: slugs.joined(separator: ",")))
            default:
                break
            }
        }
        components.queryItems = items
        return try await parseCards(url: components.url!)
    }

    func mangaDetails(mangaIDOrURL: String) async throws -> SourceMangaDetails {
        let url = mangaURL(from: mangaIDOrURL)
        let html = try await getHTML(url: url)
        let manga = Manga(
            id: mangaID(from: url.absoluteString),
            sourceID: source.id,
            title: decodeHTML(stripHTML(firstMatch(in: html, pattern: "<span[^>]*text-xl[^>]*>(.*?)</span>", options: [.dotMatchesLineSeparators, .caseInsensitive]) ?? firstMatch(in: html, pattern: "<h3[^>]*truncate[^>]*>(.*?)</h3>", options: [.dotMatchesLineSeparators, .caseInsensitive]) ?? "Untitled")),
            author: parseAsuraAuthor(html),
            summary: decodeHTML(stripHTML(firstMatch(in: html, pattern: "<span[^>]*font-medium text-sm[^>]*>(.*?)</span>", options: [.dotMatchesLineSeparators, .caseInsensitive]) ?? "")),
            genres: parseAsuraGenres(html),
            coverHexes: palette(for: url.absoluteString),
            coverURL: firstMatch(in: html, pattern: "<img[^>]+alt=[\"']poster[\"'][^>]+src=[\"']([^\"']+)[\"']"),
            statusText: parseAsuraStatus(html)
        )
        return SourceMangaDetails(manga: manga)
    }

    func chapters(for manga: Manga) async throws -> SourceChapterDetails {
        let html = try await getHTML(url: mangaURL(from: manga.id))
        let blocks = allMatches(in: html, pattern: "<div[^>]*class=[\"'][^\"']*group[^\"']*[\"'][^>]*>(.*?)</div>", options: [.dotMatchesLineSeparators, .caseInsensitive])
        let chapters: [Chapter] = blocks.enumerated().compactMap { offset, block -> Chapter? in
            guard let href = firstMatch(in: block, pattern: "href=[\"']([^\"']+)[\"']") else { return nil }
            let chapterTitle = decodeHTML(stripHTML(firstMatch(in: block, pattern: "<h3[^>]*>(.*?)</h3>", options: [.dotMatchesLineSeparators, .caseInsensitive]) ?? "Chapter \(offset + 1)"))
            let dateText = firstMatch(in: block, pattern: "<h3[^>]*>.*?</h3>\\s*<h3[^>]*>(.*?)</h3>", options: [.dotMatchesLineSeparators, .caseInsensitive]) ?? ""
            return Chapter(
                id: absoluteURL(href: href),
                mangaID: manga.id,
                title: chapterTitle,
                number: chapterNumber(from: chapterTitle, fallback: offset),
                releaseDate: parseAsuraDate(dateText),
                isDownloaded: false,
                pages: []
            )
        }.sorted { $0.number > $1.number }
        return SourceChapterDetails(chapters: chapters)
    }

    func pages(for chapter: Chapter) async throws -> SourcePageAsset {
        guard let url = URL(string: chapter.id) else { throw RuntimeSourceError.chapterPagesMissing }
        let html = try await getHTML(url: url)
        let pagesJSON = firstMatch(in: html, pattern: "\\\\\"pages\\\\\":(\\[.*?])", options: [.dotMatchesLineSeparators]) ?? ""
        let data = pagesJSON.replacingOccurrences(of: "\\\\", with: "")
        let pageDTOs = (try? JSONDecoder().decode([AsuraPageDTO].self, from: Data(data.utf8))) ?? []
        let pages = pageDTOs.sorted { $0.order < $1.order }.enumerated().map { index, page in
            ReaderPage(id: "\(chapter.id)#\(index)", index: index, title: "Page \(index + 1)", body: "", accentHex: mangaColor(index), assetKind: .image, assetPath: nil, remoteURL: page.url)
        }
        guard !pages.isEmpty else { throw RuntimeSourceError.parserEmpty }
        return SourcePageAsset(pages: pages, errorMessage: nil)
    }

    func genreTags() async throws -> [GenreTag] { [] }

    private func parseCards(url: URL) async throws -> [Manga] {
        let html = try await getHTML(url: url)
        let cards = allMatches(in: html, pattern: "<a[^>]+href=[\"']([^\"']+/series/[^\"']+)[\"'][^>]*>(.*?)</a>", options: [.dotMatchesLineSeparators, .caseInsensitive])
        let mangas = cards.compactMap { card -> Manga? in
            guard let href = firstMatch(in: card, pattern: "href=[\"']([^\"']+)[\"']") else { return nil }
            let title = firstMatch(in: card, pattern: "<span[^>]*block[^>]*>(.*?)</span>", options: [.dotMatchesLineSeparators, .caseInsensitive]) ?? "Untitled"
            let thumb = firstMatch(in: card, pattern: "<img[^>]+src=[\"']([^\"']+)[\"']")
            return Manga(id: mangaID(from: href), sourceID: source.id, title: decodeHTML(stripHTML(title)), author: "Unknown", summary: "", genres: [], coverHexes: palette(for: href), coverURL: thumb.map(absoluteURL(href:)), statusText: "Unknown")
        }
        return uniqueManga(mangas)
    }

    private func parseLatest(url: URL) async throws -> [Manga] {
        let html = try await getHTML(url: url)
        let blocks = allMatches(in: html, pattern: "<div[^>]*w-full[^>]*>(.*?)</div>", options: [.dotMatchesLineSeparators, .caseInsensitive])
        let mangas = blocks.compactMap { block -> Manga? in
            guard let href = firstMatch(in: block, pattern: "href=[\"']([^\"']+/series/[^\"']+)[\"']") else { return nil }
            let title = firstMatch(in: block, pattern: "<span[^>]*text-\\[15px\\][^>]*>\\s*<a[^>]*>(.*?)</a>", options: [.dotMatchesLineSeparators, .caseInsensitive]) ?? "Untitled"
            let thumb = firstMatch(in: block, pattern: "<img[^>]+src=[\"']([^\"']+)[\"']")
            return Manga(id: mangaID(from: href), sourceID: source.id, title: decodeHTML(stripHTML(title)), author: "Unknown", summary: "", genres: [], coverHexes: palette(for: href), coverURL: thumb.map(absoluteURL(href:)), statusText: "Unknown")
        }
        return uniqueManga(mangas)
    }

    private func parseAsuraAuthor(_ html: String) -> String {
        let author = firstMatch(in: html, pattern: "Author.*?<h3[^>]*>(.*?)</h3>", options: [.dotMatchesLineSeparators, .caseInsensitive]).map { decodeHTML(stripHTML($0)) } ?? ""
        let artist = firstMatch(in: html, pattern: "Artist.*?<h3[^>]*>(.*?)</h3>", options: [.dotMatchesLineSeparators, .caseInsensitive]).map { decodeHTML(stripHTML($0)) } ?? ""
        let joined = [author, artist].filter { !$0.isEmpty }.joined(separator: " • ")
        return joined.isEmpty ? "Unknown" : joined
    }

    private func parseAsuraGenres(_ html: String) -> [String] {
        allMatches(in: html, pattern: "<button[^>]*text-white[^>]*>(.*?)</button>", options: [.dotMatchesLineSeparators, .caseInsensitive]).map { decodeHTML(stripHTML($0)) }
    }

    private func parseAsuraStatus(_ html: String) -> String {
        firstMatch(in: html, pattern: "Status.*?<h3[^>]*>(.*?)</h3>", options: [.dotMatchesLineSeparators, .caseInsensitive]).map { decodeHTML(stripHTML($0)) } ?? "Unknown"
    }

    private func parseAsuraDate(_ text: String) -> Date {
        let cleaned = text.replacingOccurrences(of: "(\\d+)(st|nd|rd|th)", with: "$1", options: .regularExpression)
        return dateFormatter.date(from: decodeHTML(stripHTML(cleaned))) ?? .now
    }

    private func getHTML(url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue((descriptor.baseURL ?? "") + "/", forHTTPHeaderField: "Referer")
        await rateLimiter.waitTurn()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode, let html = String(data: data, encoding: .utf8) else {
            throw RuntimeSourceError.invalidResponse
        }
        return html
    }

    private func rootURL(path: String) -> URL { URL(string: (descriptor.baseURL ?? "") + path)! }
    private func absoluteURL(href: String) -> String { href.hasPrefix("http") ? href : (descriptor.baseURL ?? "") + href }
    private func mangaID(from href: String) -> String { "\(source.id)::\(URL(string: absoluteURL(href: href))?.lastPathComponent ?? href)" }
    private func mangaURL(from value: String) -> URL {
        if let url = URL(string: value), url.scheme != nil { return url }
        let slug = value.components(separatedBy: "::").last ?? value
        return rootURL(path: "/series/\(slug)")
    }
}

final class KomikIndoIDSourceEngine: SourceRuntime {
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
        try await parseArchive(url: rootURL(path: "/daftar-manga/page/\(page)/?order=popular"))
    }

    func latestManga(page: Int) async throws -> [Manga] {
        try await parseArchive(url: rootURL(path: "/daftar-manga/page/\(page)/?order=update"))
    }

    func searchManga(_ request: SourceSearchRequest) async throws -> [Manga] {
        var components = URLComponents(url: rootURL(path: "/daftar-manga/page/\(max(request.page, 1))/"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "title", value: request.query)]
        for filter in request.filters {
            switch filter {
            case .sort(let value):
                items.append(URLQueryItem(name: "order", value: value))
            case .types(let values):
                for value in values {
                    items.append(URLQueryItem(name: "type[]", value: value))
                }
            case .genreInclude(_, let slugs):
                for slug in slugs {
                    items.append(URLQueryItem(name: "genre[]", value: slug))
                }
            default:
                break
            }
        }
        components.queryItems = items
        return try await parseArchive(url: components.url!)
    }

    func mangaDetails(mangaIDOrURL: String) async throws -> SourceMangaDetails {
        let html = try await getHTML(url: mangaURL(from: mangaIDOrURL))
        let title = firstMatch(in: html, pattern: "<title>(.*?)</title>", options: [.dotMatchesLineSeparators, .caseInsensitive]) ?? "Untitled"
        let author = firstMatch(in: html, pattern: "Pengarang.*?<span[^>]*>(.*?)</span>", options: [.dotMatchesLineSeparators, .caseInsensitive]).map { decodeHTML(stripHTML($0)) } ?? "Unknown"
        let artist = firstMatch(in: html, pattern: "Ilustrator.*?<span[^>]*>(.*?)</span>", options: [.dotMatchesLineSeparators, .caseInsensitive]).map { decodeHTML(stripHTML($0)) } ?? ""
        let summary = firstMatch(in: html, pattern: "<div[^>]*entry-content entry-content-single[^>]*>(.*?)</div>", options: [.dotMatchesLineSeparators, .caseInsensitive]).map(stripHTML) ?? ""
        let genres = allMatches(in: html, pattern: "<a[^>]*>(.*?)</a>", options: [.dotMatchesLineSeparators, .caseInsensitive]).map { decodeHTML(stripHTML($0)) }
        let thumb = firstMatch(in: html, pattern: "<img[^>]+src=[\"']([^\"']+)[\"'][^>]*thumb", options: [.dotMatchesLineSeparators, .caseInsensitive]) ??
            firstMatch(in: html, pattern: "<div[^>]*thumb[^>]*>.*?<img[^>]+src=[\"']([^\"']+)[\"']", options: [.dotMatchesLineSeparators, .caseInsensitive])
        let status = firstMatch(in: html, pattern: "<span[^>]*>\\s*(Berjalan|Tamat|Ongoing|Completed)\\s*</span>", options: [.dotMatchesLineSeparators, .caseInsensitive]).map { decodeHTML(stripHTML($0)) } ?? "Unknown"
        let combinedAuthor = [author, artist].filter { !$0.isEmpty }.joined(separator: " • ")
        return SourceMangaDetails(manga: Manga(
            id: mangaID(from: mangaIDOrURL),
            sourceID: source.id,
            title: decodeHTML(stripHTML(title.replacingOccurrences(of: "\\|.*$", with: "", options: .regularExpression))),
            author: combinedAuthor.isEmpty ? "Unknown" : combinedAuthor,
            summary: summary,
            genres: Array(Set(genres)).sorted(),
            coverHexes: palette(for: mangaIDOrURL),
            coverURL: thumb.map(absoluteURL(href:)),
            statusText: status
        ))
    }

    func chapters(for manga: Manga) async throws -> SourceChapterDetails {
        let html = try await getHTML(url: mangaURL(from: manga.id))
        let items = allMatches(in: html, pattern: "<li[^>]*>(.*?)</li>", options: [.dotMatchesLineSeparators, .caseInsensitive])
        let chapters = items.enumerated().compactMap { offset, item -> Chapter? in
            guard item.contains("lchx") else { return nil }
            guard let href = firstMatch(in: item, pattern: "href=[\"']([^\"']+)[\"']") else { return nil }
            let title = firstMatch(in: item, pattern: ">([^<]+)</a>").map { decodeHTML(stripHTML($0)) } ?? "Chapter \(offset + 1)"
            let dateText = firstMatch(in: item, pattern: "<a[^>]*>(.*?)</a>\\s*</span>", options: [.dotMatchesLineSeparators, .caseInsensitive]) ?? ""
            return Chapter(
                id: absoluteURL(href: href),
                mangaID: manga.id,
                title: title,
                number: chapterNumber(from: title, fallback: offset),
                releaseDate: parseKomikIndoDate(dateText),
                isDownloaded: false,
                pages: []
            )
        }.sorted { $0.number > $1.number }
        return SourceChapterDetails(chapters: chapters)
    }

    func pages(for chapter: Chapter) async throws -> SourcePageAsset {
        guard let url = URL(string: chapter.id) else { throw RuntimeSourceError.chapterPagesMissing }
        let html = try await getHTML(url: url)
        let pages = allMatches(in: html, pattern: "src='([^']+)'", options: [.dotMatchesLineSeparators]).enumerated().map { index, url in
            ReaderPage(id: "\(chapter.id)#\(index)", index: index, title: "Page \(index + 1)", body: "", accentHex: mangaColor(index), assetKind: .image, assetPath: nil, remoteURL: absoluteURL(href: url))
        }
        guard !pages.isEmpty else { throw RuntimeSourceError.parserEmpty }
        return SourcePageAsset(pages: pages, errorMessage: nil)
    }

    func genreTags() async throws -> [GenreTag] { [] }

    private func parseArchive(url: URL) async throws -> [Manga] {
        let html = try await getHTML(url: url)
        let cards = allMatches(in: html, pattern: "<div[^>]*animepost[^>]*>(.*?)</div>", options: [.dotMatchesLineSeparators, .caseInsensitive])
        let mangas = cards.compactMap { card -> Manga? in
            guard
                let href = firstMatch(in: card, pattern: "href=[\"']([^\"']+)[\"']"),
                let title = firstMatch(in: card, pattern: "<h4[^>]*>(.*?)</h4>", options: [.dotMatchesLineSeparators, .caseInsensitive]),
                let thumb = firstMatch(in: card, pattern: "<img[^>]+src=[\"']([^\"']+)[\"']")
            else { return nil }
            return Manga(id: mangaID(from: href), sourceID: source.id, title: decodeHTML(stripHTML(title)), author: "Unknown", summary: "", genres: [], coverHexes: palette(for: href), coverURL: absoluteURL(href: thumb), statusText: "Unknown")
        }
        return uniqueManga(mangas)
    }

    private func parseKomikIndoDate(_ text: String) -> Date {
        let cleaned = decodeHTML(stripHTML(text))
        if let value = Int(cleaned.components(separatedBy: " ").first ?? "") {
            if cleaned.contains("hari") { return Calendar.current.date(byAdding: .day, value: -value, to: .now) ?? .now }
            if cleaned.contains("jam") { return Calendar.current.date(byAdding: .hour, value: -value, to: .now) ?? .now }
            if cleaned.contains("menit") { return Calendar.current.date(byAdding: .minute, value: -value, to: .now) ?? .now }
        }
        return dateFormatter.date(from: cleaned) ?? .now
    }

    private func getHTML(url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue((descriptor.baseURL ?? "") + "/", forHTTPHeaderField: "Referer")
        await rateLimiter.waitTurn()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode, let html = String(data: data, encoding: .utf8) else {
            throw RuntimeSourceError.invalidResponse
        }
        return html
    }

    private func rootURL(path: String) -> URL { URL(string: (descriptor.baseURL ?? "") + path)! }
    private func absoluteURL(href: String) -> String { href.hasPrefix("http") ? href : (descriptor.baseURL ?? "") + (href.hasPrefix("/") ? href : "/\(href)") }
    private func mangaID(from href: String) -> String { "\(source.id)::\(URL(string: absoluteURL(href: href))?.lastPathComponent ?? href)" }
    private func mangaURL(from value: String) -> URL {
        if let url = URL(string: value), url.scheme != nil { return url }
        return URL(string: absoluteURL(href: value.components(separatedBy: "::").last ?? value))!
    }
}

final class NHentaiSourceEngine: SourceRuntime {
    let source: Source

    private let descriptor: SourceDescriptor
    private let session: URLSession
    private let rateLimiter: SourceRateLimiter

    init(source: Source, descriptor: SourceDescriptor, session: URLSession = .shared) {
        self.source = source
        self.descriptor = descriptor
        self.session = session
        self.rateLimiter = SourceRateLimiter(requestsPerSecond: max(descriptor.context?.requestPolicy.rateLimit ?? 4, 1))
    }

    func popularManga(page: Int) async throws -> [Manga] {
        try await parseGallery(url: rootURL(path: "/search/?q=%22%22&sort=popular&page=\(page)"))
    }

    func latestManga(page: Int) async throws -> [Manga] {
        try await parseGallery(url: rootURL(path: "/?page=\(page)"))
    }

    func searchManga(_ request: SourceSearchRequest) async throws -> [Manga] {
        let trimmed = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("id:") || Int(trimmed) != nil {
            let id = trimmed.replacingOccurrences(of: "id:", with: "")
            let details = try await mangaDetails(mangaIDOrURL: "/g/\(id)")
            return [details.manga]
        }
        var components = URLComponents(url: rootURL(path: "/search/"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed.isEmpty ? "\"\"" : trimmed),
            URLQueryItem(name: "page", value: String(max(request.page, 1))),
        ]
        if case let .sort(value)? = request.filters.first(where: {
            if case .sort = $0 { return true }
            return false
        }) {
            components.queryItems?.append(URLQueryItem(name: "sort", value: value))
        }
        return try await parseGallery(url: components.url!)
    }

    func mangaDetails(mangaIDOrURL: String) async throws -> SourceMangaDetails {
        let url = mangaURL(from: mangaIDOrURL)
        let html = try await getHTML(url: url)
        let data = try extractNHentaiData(html: html)
        let cdn = extractNHentaiCDNs(html: html, thumbnails: true).first
        let title = data.title.pretty ?? data.title.english ?? data.title.japanese ?? "Untitled"
        let thumb = cdn.map { "https://\($0)/galleries/\(data.mediaID)/1t.\(data.images.pages.first?.extension ?? "jpg")" }
        let tags = data.tags.filter { $0.type == "tag" }.map(\.name)
        let artists = data.tags.filter { $0.type == "artist" }.map(\.name).joined(separator: ", ")
        let groups = data.tags.filter { $0.type == "group" }.map(\.name).joined(separator: ", ")
        let author = [groups, artists].filter { !$0.isEmpty }.joined(separator: " • ")
        let summary = "Pages: \(data.images.pages.count)\nFavorited by: \(data.numFavorites)\n\n\(tags.joined(separator: ", "))"
        return SourceMangaDetails(manga: Manga(
            id: mangaID(from: url.absoluteString),
            sourceID: source.id,
            title: title,
            author: author.isEmpty ? "Unknown" : author,
            summary: summary,
            genres: tags,
            coverHexes: palette(for: url.absoluteString),
            coverURL: thumb,
            statusText: "Completed"
        ))
    }

    func chapters(for manga: Manga) async throws -> SourceChapterDetails {
        let url = mangaURL(from: manga.id)
        let uploadDate: Date
        do {
            let html = try await getHTML(url: url)
            let data = try extractNHentaiData(html: html)
            uploadDate = Date(timeIntervalSince1970: TimeInterval(data.uploadDate))
        } catch {
            uploadDate = .now
        }
        return SourceChapterDetails(chapters: [
            Chapter(
                id: url.absoluteString,
                mangaID: manga.id,
                title: "Chapter",
                number: 1,
                releaseDate: uploadDate,
                isDownloaded: false,
                pages: []
            )
        ])
    }

    func pages(for chapter: Chapter) async throws -> SourcePageAsset {
        guard let url = URL(string: chapter.id) else { throw RuntimeSourceError.chapterPagesMissing }
        let html = try await getHTML(url: url)
        let data = try extractNHentaiData(html: html)
        let cdn = extractNHentaiCDNs(html: html, thumbnails: false).first
        guard let cdn else { throw RuntimeSourceError.parserEmpty }
        let pages = data.images.pages.enumerated().map { index, image in
            ReaderPage(
                id: "\(chapter.id)#\(index)",
                index: index,
                title: "Page \(index + 1)",
                body: "",
                accentHex: mangaColor(index),
                assetKind: .image,
                assetPath: nil,
                remoteURL: "https://\(cdn)/galleries/\(data.mediaID)/\(index + 1).\(image.extension)"
            )
        }
        return SourcePageAsset(pages: pages, errorMessage: nil)
    }

    func genreTags() async throws -> [GenreTag] { [] }

    private func parseGallery(url: URL) async throws -> [Manga] {
        let html = try await getHTML(url: url)
        let pattern = #"<div[^>]*class=["'][^"']*gallery[^"']*["'][^>]*>.*?<a[^>]*href=["'](/g/\d+/? )["'][^>]*>.*?<img[^>]*?(?:data-src|data-cfsrc|src)=["']([^"']+)["'][^>]*>.*?</a>.*?<div[^>]*class=["'][^"']*caption[^"']*["'][^>]*>(.*?)</div>.*?</div>"#
            .replacingOccurrences(of: "/? )", with: "/?)")
        let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let mangas = (regex?.matches(in: html, range: range) ?? []).compactMap { match -> Manga? in
            guard
                match.numberOfRanges >= 4,
                let hrefRange = Range(match.range(at: 1), in: html),
                let thumbRange = Range(match.range(at: 2), in: html),
                let titleRange = Range(match.range(at: 3), in: html)
            else {
                return nil
            }
            let href = String(html[hrefRange])
            let thumb = String(html[thumbRange])
            let title = stripHTML(String(html[titleRange]))
            return Manga(
                id: mangaID(from: href),
                sourceID: source.id,
                title: decodeHTML(title.isEmpty ? "Untitled" : title),
                author: "Unknown",
                summary: "",
                genres: [],
                coverHexes: palette(for: href),
                coverURL: normalizedRemoteURL(thumb),
                statusText: "Completed"
            )
        }
        return uniqueManga(mangas)
    }

    private func getHTML(url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue((descriptor.baseURL ?? "") + "/", forHTTPHeaderField: "Referer")
        await rateLimiter.waitTurn()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode, let html = String(data: data, encoding: .utf8) else {
            throw RuntimeSourceError.invalidResponse
        }
        return html
    }

    private func rootURL(path: String) -> URL { URL(string: (descriptor.baseURL ?? "") + path)! }
    private func mangaURL(from value: String) -> URL {
        if value.contains("::") {
            let id = value.components(separatedBy: "::").last ?? value
            return rootURL(path: "/g/\(id)")
        }
        if let url = URL(string: value), url.scheme != nil { return url }
        if value.hasPrefix("/g/") { return rootURL(path: value) }
        let id = value.components(separatedBy: "::").last ?? value
        return rootURL(path: "/g/\(id)")
    }
    private func mangaID(from href: String) -> String {
        let absolute = href.hasPrefix("http") ? href : (descriptor.baseURL ?? "") + href
        let id = absolute.components(separatedBy: "/").filter { !$0.isEmpty }.last ?? absolute
        return "\(source.id)::\(id)"
    }

    private func normalizedRemoteURL(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        if value.hasPrefix("//") {
            return "https:\(value)"
        }
        if value.hasPrefix("/") {
            return (descriptor.baseURL ?? "") + value
        }
        return value
    }

    private func extractNHentaiData(html: String) throws -> NHentaiGalleryDTO {
        let scripts = allMatches(
            in: html,
            pattern: "<script[^>]*>(.*?)</script>",
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        )
        let candidateScript = scripts.first {
            $0.contains("JSON.parse") &&
            !$0.contains("media_server") &&
            !$0.contains("avatar_url")
        }
        guard
            let scriptSource = candidateScript ?? firstMatch(
                in: html,
                pattern: "(JSON\\.parse\\(\\s*\\\".*\\\"\\s*\\))",
                options: [.dotMatchesLineSeparators]
            ),
            let script = extractJSONStringArgument(fromJSONParseCall: scriptSource),
            let data = RegexUnicodeUnescaper.unescape(script).data(using: .utf8)
        else {
            throw RuntimeSourceError.parserEmpty
        }
        return try JSONDecoder().decode(NHentaiGalleryDTO.self, from: data)
    }

    private func extractNHentaiCDNs(html: String, thumbnails: Bool) -> [String] {
        let pattern = thumbnails ? "thumb_cdn_urls:\\s*(\\[.*?\\])" : "image_cdn_urls:\\s*(\\[.*?\\])"
        guard let json = firstMatch(in: html, pattern: pattern, options: [.dotMatchesLineSeparators]), let data = json.data(using: .utf8) else {
            return []
        }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}

struct UnsupportedSourceEngine: SourceEngine {
    let family: SourceEngineFamily

    func makeRuntime(from descriptor: SourceDescriptor, source: Source) throws -> any SourceRuntime {
        UnsupportedFamilyRuntime(source: source, family: family)
    }
}

struct SourceRuntimeRegistry {
    private let descriptorsBySourceID: [String: SourceDescriptor]
    private let sourcesByID: [String: Source]
    private let engines: [SourceEngineFamily: any SourceEngine]

    init(sources: [Source], descriptors: [SourceDescriptor]) {
        self.descriptorsBySourceID = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.sourceID, $0) })
        self.sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        self.engines = [
            .natsuId: NatsuIdRuntimeFactory(),
            .madara: MadaraRuntimeFactory(),
            .mangaThemesia: MangaThemesiaRuntimeFactory(),
            .mangaBox: MangaBoxRuntimeFactory(),
            .asuraScans: AsuraScansRuntimeFactory(),
            .komikIndoID: KomikIndoIDRuntimeFactory(),
            .nhentai: NHentaiRuntimeFactory(),
            .zeistManga: UnsupportedSourceEngine(family: .zeistManga),
            .fmReader: UnsupportedSourceEngine(family: .fmReader),
            .foolSlide: UnsupportedSourceEngine(family: .foolSlide),
            .newToki: UnsupportedSourceEngine(family: .newToki),
            .customParsed: UnsupportedSourceEngine(family: .customParsed),
        ]
    }

    func runtime(for sourceID: String) -> (any SourceRuntime)? {
        guard
            let source = sourcesByID[sourceID],
            let descriptor = descriptorsBySourceID[sourceID],
            let engine = engines[descriptor.engineFamily]
        else {
            return nil
        }
        return try? engine.makeRuntime(from: descriptor, source: source)
    }
}

final class RuntimeSourceRepository: SourceRepository, SourceCatalogRuntime {
    private let fallback: InternalSourceRepository
    private let mergedSources: [Source]
    private let mergedDescriptors: [SourceDescriptor]
    private let registry: SourceRuntimeRegistry

    init(
        fallback: InternalSourceRepository = InternalSourceRepository(),
        repoRecords: [SourceRepoRecord] = []
    ) {
        self.fallback = fallback
        let merged = SourceRegistryBuilder().build(
            internalSources: fallback.sources(),
            internalDescriptors: fallback.descriptors(),
            repoRecords: repoRecords.filter { $0.lastError == nil }
        )
        self.mergedSources = merged.0
        self.mergedDescriptors = merged.1
        self.registry = SourceRuntimeRegistry(sources: merged.0, descriptors: merged.1)
    }

    func sources() -> [Source] {
        mergedSources
    }

    func descriptors() -> [SourceDescriptor] {
        mergedDescriptors
    }

    func descriptor(for sourceID: String) -> SourceDescriptor? {
        mergedDescriptors.first { $0.sourceID == sourceID }
    }

    func mangas(for sourceID: String) -> [Manga] {
        fallback.mangas(for: sourceID)
    }

    func chapters(for mangaID: String) -> [Chapter] {
        fallback.chapters(for: mangaID)
    }

    func activeSources() -> [Source] {
        mergedSources.filter(\.isEnabled)
    }

    func popularManga(sourceID: String) async throws -> [Manga] {
        guard let runtime = registry.runtime(for: sourceID) else {
            return try await fallback.popularManga(sourceID: sourceID)
        }
        return try await runtime.popularManga(page: 1)
    }

    func latestManga(sourceID: String) async throws -> [Manga] {
        guard let runtime = registry.runtime(for: sourceID) else {
            return try await fallback.latestManga(sourceID: sourceID)
        }
        return try await runtime.latestManga(page: 1)
    }

    func searchManga(sourceID: String, query: String, filters: [SourceFilterValue]) async throws -> [Manga] {
        guard let runtime = registry.runtime(for: sourceID) else {
            return try await fallback.searchManga(sourceID: sourceID, query: query, filters: filters)
        }
        return try await runtime.searchManga(SourceSearchRequest(query: query, page: 1, filters: filters))
    }

    func mangaDetails(sourceID: String, mangaIDOrURL: String) async throws -> SourceMangaDetails {
        guard let runtime = registry.runtime(for: sourceID) else {
            return try await fallback.mangaDetails(sourceID: sourceID, mangaIDOrURL: mangaIDOrURL)
        }
        return try await runtime.mangaDetails(mangaIDOrURL: mangaIDOrURL)
    }

    func chapters(sourceID: String, manga: Manga) async throws -> SourceChapterDetails {
        guard let runtime = registry.runtime(for: sourceID) else {
            return try await fallback.chapters(sourceID: sourceID, manga: manga)
        }
        return try await runtime.chapters(for: manga)
    }

    func pages(sourceID: String, chapter: Chapter) async throws -> SourcePageAsset {
        guard let runtime = registry.runtime(for: sourceID) else {
            return try await fallback.pages(sourceID: sourceID, chapter: chapter)
        }
        return try await runtime.pages(for: chapter)
    }

    func genreTags(sourceID: String) async throws -> [GenreTag] {
        guard let runtime = registry.runtime(for: sourceID) else {
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

private struct MangaBoxAPIResponse: Decodable {
    let data: MangaBoxAPIData
}

private struct MangaBoxAPIData: Decodable {
    let chapters: [MangaBoxAPIChapter]
}

private struct MangaBoxAPIChapter: Decodable {
    let chapterName: String
    let chapterSlug: String
    let chapterNum: Float
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case chapterName = "chapter_name"
        case chapterSlug = "chapter_slug"
        case chapterNum = "chapter_num"
        case updatedAt = "updated_at"
    }
}

private struct AsuraPageDTO: Decodable {
    let order: Int
    let url: String
}

private struct NHentaiGalleryDTO: Decodable {
    let mediaID: String
    let title: NHentaiTitleDTO
    let images: NHentaiImagesDTO
    let tags: [NHentaiTagDTO]
    let uploadDate: Int
    let numFavorites: Int

    enum CodingKeys: String, CodingKey {
        case mediaID = "media_id"
        case title
        case images
        case tags
        case uploadDate = "upload_date"
        case numFavorites = "num_favorites"
    }
}

private struct NHentaiTitleDTO: Decodable {
    let english: String?
    let japanese: String?
    let pretty: String?
}

private struct NHentaiImagesDTO: Decodable {
    let pages: [NHentaiImageDTO]
}

private struct NHentaiImageDTO: Decodable {
    let type: String

    var `extension`: String {
        switch type {
        case "w":
            return "webp"
        case "p":
            return "png"
        case "g":
            return "gif"
        default:
            return "jpg"
        }
    }
}

private struct NHentaiTagDTO: Decodable {
    let type: String
    let name: String
}

private enum RegexUnicodeUnescaper {
    static func unescape(_ value: String) -> String {
        var result = value.replacingOccurrences(of: "\\\"", with: "\"")
        result = result.replacingOccurrences(of: "\\/", with: "/")
        return result.unicodeEscaped()
    }
}

private func extractJSONStringArgument(fromJSONParseCall script: String) -> String? {
    guard let parseRange = script.range(of: "JSON.parse(") else { return nil }
    let tail = script[parseRange.upperBound...]
    guard let openingQuote = tail.firstIndex(of: "\"") else { return nil }

    var cursor = tail.index(after: openingQuote)
    var escaped = false
    var output = ""

    while cursor < tail.endIndex {
        let character = tail[cursor]
        if escaped {
            output.append("\\")
            output.append(character)
            escaped = false
        } else if character == "\\" {
            escaped = true
        } else if character == "\"" {
            return output
        } else {
            output.append(character)
        }
        cursor = tail.index(after: cursor)
    }

    return nil
}

private extension String {
    func unicodeEscaped() -> String {
        let pattern = "\\\\u([0-9A-Fa-f]{4})"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }
        let ns = self as NSString
        let matches = regex.matches(in: self, range: NSRange(location: 0, length: ns.length)).reversed()
        var output = self
        for match in matches {
            let hex = ns.substring(with: match.range(at: 1))
            if let scalar = UInt32(hex, radix: 16), let unicode = UnicodeScalar(scalar), let range = Range(match.range, in: output) {
                output.replaceSubrange(range, with: String(Character(unicode)))
            }
        }
        return output
    }
}

private func firstMatch(in text: String, pattern: String, options: NSRegularExpression.Options = []) -> String? {
    let regex = try? NSRegularExpression(pattern: pattern, options: options)
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard
        let match = regex?.firstMatch(in: text, range: range),
        match.numberOfRanges > 1,
        let capture = Range(match.range(at: 1), in: text)
    else {
        return nil
    }
    return String(text[capture])
}

private func allMatches(in text: String, pattern: String, options: NSRegularExpression.Options = []) -> [String] {
    let regex = try? NSRegularExpression(pattern: pattern, options: options)
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return (regex?.matches(in: text, range: range) ?? []).compactMap { match in
        guard match.numberOfRanges > 1, let capture = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[capture])
    }
}

private func stripHTML(_ html: String) -> String {
    let withoutTags = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    return decodeHTML(withoutTags)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func decodeHTML(_ text: String) -> String {
    text
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&nbsp;", with: " ")
}

private func chapterNumber(from title: String, fallback: Int) -> Double {
    guard let raw = firstMatch(in: title, pattern: "(\\d+(?:\\.\\d+)?)"), let number = Double(raw) else {
        return Double(max(1, 10_000 - fallback))
    }
    return number
}

private func palette(for seed: String) -> [String] {
    let palette: [[String]] = [
        ["#F97316", "#431407"],
        ["#10B981", "#052E16"],
        ["#3B82F6", "#172554"],
        ["#E879F9", "#3B0764"],
        ["#FACC15", "#422006"],
        ["#22D3EE", "#083344"],
    ]
    let index = abs(seed.hashValue) % palette.count
    return palette[index]
}

private func mangaColor(_ index: Int) -> String {
    let colors = ["#5C8CFF", "#7CA8FF", "#A3C2FF", "#1D3F72", "#3C8D7B", "#9FE1D1"]
    return colors[index % colors.count]
}

private func uniqueManga(_ mangas: [Manga]) -> [Manga] {
    var seen = Set<String>()
    return mangas.filter { seen.insert($0.id).inserted }
}

private func extractArrayValues(from text: String, name: String) -> [String] {
    guard let raw = firstMatch(in: text, pattern: "\(name)\\s*=\\s*\\[([^\\]]+)]", options: [.dotMatchesLineSeparators]) else {
        return []
    }
    return raw
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .map { $0.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\\/", with: "/") }
        .filter { !$0.isEmpty }
}

private func extractImagePages(from html: String, chapterID: String) -> [ReaderPage] {
    allMatches(in: html, pattern: "<img[^>]+src=[\"']([^\"']+)[\"']", options: [.dotMatchesLineSeparators, .caseInsensitive])
        .enumerated()
        .map { index, url in
            ReaderPage(id: "\(chapterID)#\(index)", index: index, title: "Page \(index + 1)", body: "", accentHex: mangaColor(index), assetKind: .image, assetPath: nil, remoteURL: url)
        }
}
