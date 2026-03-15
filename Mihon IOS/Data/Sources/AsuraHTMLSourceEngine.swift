//
//  AsuraHTMLSourceEngine.swift
//  Mihon IOS
//

import Foundation

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
            "User-Agent": SourceEngineUtilities.defaultUserAgent,
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
        let slug = SourceEngineUtilities.slug(from: mangaIDOrURL)
        let title = SourceEngineUtilities.titleFromSlug(slug)
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
        return SourceChapterDetails(chapters: [])
    }

    func pages(for chapter: Chapter) async throws -> SourcePageAsset {
        return SourcePageAsset(pages: [], errorMessage: "Pages not implemented for this source yet.")
    }

    func genreTags() async throws -> [GenreTag] { [] }

    // MARK: - Networking

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

    // MARK: - Shared HTML parsing (used by AsuraAPISourceEngine)

    /// Parses series listing from Asura's RSC-rendered HTML.
    /// Extracts slug, cover URL, title, status, and latest chapter from
    /// the serialized React Server Component payload in the page.
    static func mapSeriesList(html: String, sourceID: String) -> [Manga] {
        // Strategy 1: Parse series data from RSC payload.
        // The RSC payload contains patterns like:
        //   "href":"series/<slug>"    → slug
        //   "src":"https://gg.asuracomic.net/storage/media/...thumb-small.webp" → cover
        // Titles and other metadata appear as text nodes near the slug.
        
        // Find all series slugs in href patterns
        // Slugs look like: the-extras-academy-survival-guide-90358a23
        let slugPattern = #"(?:href|"href")[=:]\\?"?/?series/([a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])"#
        let slugRegex = try? NSRegularExpression(pattern: slugPattern, options: [.caseInsensitive])
        let htmlRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let slugMatches = slugRegex?.matches(in: html, range: htmlRange) ?? []
        
        // Collect unique slugs preserving order
        var seenSlugs = Set<String>()
        var slugs: [String] = []
        for match in slugMatches {
            guard let range = Range(match.range(at: 1), in: html) else { continue }
            let slug = String(html[range])
            // Skip common non-series paths
            if slug == "series" || slug.count < 3 { continue }
            if seenSlugs.insert(slug).inserted {
                slugs.append(slug)
            }
        }
        
        // Build a map of cover URLs: find all thumb-small.webp image URLs
        // and associate them with nearby slugs by looking at their position in the HTML
        let coverPattern = #"https://gg\.asuracomic\.net/storage/media/\d+/conversions/[^"\\]+thumb-small\.webp"#
        let coverRegex = try? NSRegularExpression(pattern: coverPattern, options: [])
        let coverMatches = coverRegex?.matches(in: html, range: htmlRange) ?? []
        var coverURLs: [String] = []
        for match in coverMatches {
            guard let range = Range(match.range, in: html) else { continue }
            let url = String(html[range])
            coverURLs.append(url)
        }
        
        // Extract titles: look for text patterns near series slugs
        // In RSC payload, titles appear as children text like:
        //   "children":"The Extra's Academy Survival Guide"
        // or as bold span text
        let titlePattern = #""children"\\?:\s*\\?"([^"\\]{3,100})\\?""#
        let titleRegex = try? NSRegularExpression(pattern: titlePattern, options: [])
        let titleMatches = titleRegex?.matches(in: html, range: htmlRange) ?? []
        var allTitles: [(title: String, location: Int)] = []
        for match in titleMatches {
            guard let range = Range(match.range(at: 1), in: html) else { continue }
            let title = String(html[range])
            // Filter out non-title strings (CSS classes, HTML tags, short strings)
            if title.contains("text-") || title.contains("bg-") || title.contains("class") ||
               title.contains("http") || title.contains("{") || title.contains("<") ||
               title.hasPrefix("Chapter") || title.hasPrefix("status") { continue }
            allTitles.append((title: title, location: match.range.location))
        }
        
        // For each slug, find the nearest title that appears before it
        // and the cover URL at the corresponding index
        var items: [Manga] = []
        for (index, slug) in slugs.enumerated() {
            // Find slug position in HTML
            let slugSearchStr = "series/\(slug)"
            let slugLocation = (html as NSString).range(of: slugSearchStr).location
            
            // Find the nearest title before this slug position
            var bestTitle: String?
            var bestDistance = Int.max
            for (title, loc) in allTitles {
                let distance = abs(slugLocation - loc)
                if distance < bestDistance {
                    bestDistance = distance
                    bestTitle = title
                }
            }
            
            let title = bestTitle ?? SourceEngineUtilities.titleFromSlug(slug)
            let coverURL = index < coverURLs.count ? coverURLs[index] : nil
            
            let manga = Manga(
                id: "\(sourceID)::\(slug)",
                sourceID: sourceID,
                title: title,
                author: "Unknown",
                summary: "",
                genres: ["Manhwa"],
                coverHexes: SourceEngineUtilities.palette(for: slug),
                coverURL: coverURL,
                statusText: "Unknown"
            )
            items.append(manga)
        }
        
        return items
    }
}
