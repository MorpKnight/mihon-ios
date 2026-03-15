//
// AsuraLegacyEngines.swift
// Extracted from rs-asurascan branch
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

