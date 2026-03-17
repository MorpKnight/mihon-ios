//
//  AsuraAPISourceEngine.swift
//  Mihon IOS
//

import Foundation

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
        let config = SourceEngineUtilities.sessionConfiguration(additionalHeaders: [
            "User-Agent": SourceEngineUtilities.defaultUserAgent,
            "Accept-Language": "en-US,en;q=0.9",
            "Accept": "application/json, text/html;q=0.1,*/*;q=0.1",
            "Referer": baseURL + "/"
        ])
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    func popularManga(page: Int) async throws -> [Manga] {
        let htmlURL = URL(string: baseURL + "/series?genres=&status=-1&types=-1&order=rating&page=\(page)")!
        let html = try await getHTML(url: htmlURL)
        return AsuraHTMLSourceEngine.mapSeriesList(html: html, sourceID: source.id)
    }

    func latestManga(page: Int) async throws -> [Manga] {
        let htmlURL = URL(string: baseURL + "/page/\(page)")!
        let html = try await getHTML(url: htmlURL)
        return AsuraHTMLSourceEngine.mapSeriesList(html: html, sourceID: source.id)
    }

    func searchManga(_ request: SourceSearchRequest) async throws -> [Manga] {
        var components = URLComponents(string: baseURL + "/series")!
        components.queryItems = [URLQueryItem(name: "page", value: String(request.page))]
        let q = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { components.queryItems?.append(URLQueryItem(name: "name", value: q)) }
        let html = try await getHTML(url: components.url!)
        return AsuraHTMLSourceEngine.mapSeriesList(html: html, sourceID: source.id)
    }

    func mangaDetails(mangaIDOrURL: String) async throws -> SourceMangaDetails {
        let slug = SourceEngineUtilities.slug(from: mangaIDOrURL)
        debugLog("mangaDetails for slug: \(slug)")
        
        let seriesURL = URL(string: baseURL + "/series/\(slug)")!
        debugLog("Fetching series page: \(seriesURL.absoluteString)")
        let html = try await getHTML(url: seriesURL)
        
        debugLog("HTML length: \(html.count) characters")
        
        // 1. Try __NEXT_DATA__
        let nextDataPattern = "<script id=\"__NEXT_DATA__\" type=\"application/json\">([\\s\\S]*?)</script>"
        if let nextDataJSON = SourceEngineUtilities.firstMatch(in: html, pattern: nextDataPattern, options: [.dotMatchesLineSeparators]) {
            debugLog("Found __NEXT_DATA__, attempting to parse")
            return try await parseFromNextData(html: html, slug: slug, nextDataJSON: nextDataJSON)
        }
        
        // 2. Try to find embedded JSON in script tags
        debugLog("No __NEXT_DATA__ found, trying alternative script tags...")
        let scriptPattern = "<script[^>]*>([\\s\\S]*?)</script>"
        let allScripts = SourceEngineUtilities.allMatches(in: html, pattern: scriptPattern, options: [.dotMatchesLineSeparators])
        debugLog("Found \(allScripts.count) script tags")
        
        for (index, script) in allScripts.enumerated() {
            if script.contains("\"series\"") && script.contains("\"title\"") {
                debugLog("Found potential series data in script tag #\(index)")
                debugLog("Script preview: \(script.prefix(200))...")
                break
            }
        }
        
        // 3. Fall back to HTML scraping
        debugLog("Falling back to HTML scraping")
        return try parseFromHTML(html: html, slug: slug)
    }
    
    private func parseFromNextData(html: String, slug: String, nextDataJSON: String) async throws -> SourceMangaDetails {
        guard let jsonData = nextDataJSON.data(using: .utf8) else {
            debugLog("Failed to convert JSON string to Data")
            throw RuntimeSourceError.invalidResponse
        }
        
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
            debugLog("Successfully decoded NextData")
        } catch {
            debugLog("Failed to decode NextData: \(error)")
            throw RuntimeSourceError.invalidResponse
        }
        
        guard let series = nextData.props.pageProps.series else {
            debugLog("No series data in pageProps")
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
            summary: SourceEngineUtilities.stripHTML(description),
            genres: genres,
            coverHexes: SourceEngineUtilities.palette(for: slug),
            coverURL: coverURL,
            statusText: status
        )
        
        return SourceMangaDetails(manga: manga)
    }
    
    private func parseFromHTML(html: String, slug: String) throws -> SourceMangaDetails {
        debugLog("Parsing manga details from HTML...")
        
        var title = slug.replacingOccurrences(of: "-", with: " ").capitalized
        if let h1 = SourceEngineUtilities.firstMatch(in: html, pattern: "<h1[^>]*>([^<]+)</h1>", options: [.dotMatchesLineSeparators, .caseInsensitive]) {
            title = SourceEngineUtilities.stripHTML(h1)
            debugLog("Found title: \(title)")
        }
        
        var coverURL: String?
        if let imgSrc = SourceEngineUtilities.firstMatch(in: html, pattern: "<img[^>]*alt=\"[^\"]*cover[^\"]*\"[^>]*src=\"([^\"]+)\"", options: [.caseInsensitive]) {
            coverURL = imgSrc
            debugLog("Found cover: \(imgSrc)")
        } else if let ogImage = SourceEngineUtilities.firstMatch(in: html, pattern: "property=\"og:image\"[^>]*content=\"([^\"]+)\"") {
            coverURL = ogImage
            debugLog("Found OG image: \(ogImage)")
        }
        
        var description = "No description available."
        if let desc = SourceEngineUtilities.firstMatch(in: html, pattern: "<div[^>]*class=\"[^\"]*description[^\"]*\"[^>]*>([\\s\\S]{50,2000}?)</div>", options: [.dotMatchesLineSeparators, .caseInsensitive]) {
            description = SourceEngineUtilities.stripHTML(desc)
            debugLog("Found description: \(description.prefix(100))...")
        }
        
        let manga = Manga(
            id: "\(source.id)::\(slug)",
            sourceID: source.id,
            title: title,
            author: "Unknown",
            summary: description,
            genres: ["Manhwa"],
            coverHexes: SourceEngineUtilities.palette(for: slug),
            coverURL: coverURL,
            statusText: "Unknown"
        )
        
        debugLog("Manga created from HTML: \(manga.title)")
        return SourceMangaDetails(manga: manga)
    }

    func chapters(for manga: Manga) async throws -> SourceChapterDetails {
        let slug = SourceEngineUtilities.slug(from: manga.id)
        debugLog("chapters() for manga: \(manga.title), slug: \(slug)")
        
        // First, try using the API directly
        do {
            debugLog("Trying API endpoint for chapters...")
            let data = try await getJSON(path: "/api/series/\(slug)/chapters", ttl: 60 * 15)
            if !data.isEmpty {
                debugLog("Got response from chapters API")
                
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
                    debugLog("Decoded \(chapterDTOs.count) chapters from API")
                    
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
            debugLog("API request failed: \(error), falling back to HTML")
        }
        
        // Fall back to HTML scraping
        let seriesURL = URL(string: baseURL + "/series/\(slug)")!
        let html = try await getHTML(url: seriesURL)
        
        debugLog("HTML length: \(html.count) characters")
        
        // Try to extract chapter data from __NEXT_DATA__
        debugLog("Attempting to extract chapters from __NEXT_DATA__...")
        let nextDataPattern = "<script id=\"__NEXT_DATA__\" type=\"application/json\">([\\s\\S]*?)</script>"
        if let nextDataJSON = SourceEngineUtilities.firstMatch(in: html, pattern: nextDataPattern, options: [.dotMatchesLineSeparators]) {
            debugLog("Found __NEXT_DATA__ in series page")
            
            do {
                let chapters = try parseChaptersFromNextData(nextDataJSON: nextDataJSON, slug: slug, mangaID: manga.id)
                if !chapters.isEmpty {
                    debugLog("Successfully extracted \(chapters.count) chapters from __NEXT_DATA__")
                    return SourceChapterDetails(chapters: chapters)
                } else {
                    debugLog("__NEXT_DATA__ found but no chapters extracted")
                }
            } catch {
                debugLog("Failed to parse __NEXT_DATA__: \(error)")
            }
        } else {
            debugLog("No __NEXT_DATA__ found in series page")
        }
        
        // Save a snippet of HTML to inspect structure
        if html.count > 1000 {
            let snippet = String(html.prefix(2000))
            if snippet.lowercased().contains("chapter") {
                debugLog("HTML contains 'chapter' keyword - looking for structure...")
                if let chapterListMatch = SourceEngineUtilities.firstMatch(in: snippet, pattern: "(<div[^>]*chapter[^>]*>.*)", options: [.caseInsensitive]) {
                    debugLog("Found chapter container: \(chapterListMatch.prefix(200))")
                }
            }
        }
        
        // Try multiple patterns for chapter links
        var matches: [[String]] = []
        
        // Pattern 1: /series/{slug}/chapter/{chapter-slug}
        debugLog("Trying pattern 1: /series/.../chapter/...")
        var chapterPattern = "<a[^>]*href=\"/series/[^/]+/chapter/([^\"]+)\"[^>]*>([\\s\\S]*?)</a>"
        matches = SourceEngineUtilities.allMatchesWithGroups(in: html, pattern: chapterPattern, groupCount: 2)
        debugLog("Pattern 1 found \(matches.count) matches")
        
        if matches.isEmpty {
            // Pattern 2: href="/series/{slug}/{chapter-slug}"
            debugLog("Trying pattern 2: /series/\(slug)/...")
            chapterPattern = "href=\"/series/\(slug.replacingOccurrences(of: "-", with: "\\-"))/([^\"]+)\""
            matches = SourceEngineUtilities.allMatchesWithGroups(in: html, pattern: chapterPattern, groupCount: 1)
            debugLog("Pattern 2 found \(matches.count) matches")
        }
        
        if matches.isEmpty {
            // Pattern 3: Look for any link containing "chapter" in the href
            debugLog("Trying pattern 3: any link with 'chapter'...")
            chapterPattern = "href=\"([^\"]*chapter[^\"]+)\""
            let chapterURLs = SourceEngineUtilities.allMatches(in: html, pattern: chapterPattern, options: [])
            debugLog("Pattern 3 found \(chapterURLs.count) potential chapter URLs")
            
            let validChapterURLs = chapterURLs.filter { url in
                url.contains(slug) && url.contains("chapter/")
            }
            
            let uniqueURLs = Array(Set(validChapterURLs))
            
            if !uniqueURLs.isEmpty {
                debugLog("After filtering: \(uniqueURLs.count) unique chapter URLs")
                debugLog("Sample raw URLs: \(uniqueURLs.prefix(5).joined(separator: " | "))")
                
                if let firstURL = uniqueURLs.first {
                    let testURL: String
                    if firstURL.hasPrefix("http") {
                        testURL = firstURL
                    } else if firstURL.hasPrefix("/") {
                        testURL = baseURL + firstURL
                    } else if firstURL.hasPrefix("series/") {
                        testURL = baseURL + "/" + firstURL
                    } else {
                        testURL = baseURL + "/series/" + firstURL
                    }
                    debugLog("First URL will be: \(testURL)")
                }
                
                matches = uniqueURLs.map { [$0] }
            }
        }
        
        if matches.isEmpty {
            // Pattern 4: Try finding data-* attributes
            debugLog("Trying pattern 4: looking for data attributes...")
            let dataPattern = "data-chapter[^>]*=\\\"([^\\\"]+)\\\""
            let dataChapters = SourceEngineUtilities.allMatches(in: html, pattern: dataPattern, options: [])
            debugLog("Found \(dataChapters.count) data-chapter attributes")
        }
        
        debugLog("Final match count: \(matches.count)")
        
        var chapters: [Chapter] = []
        for (index, groups) in matches.enumerated() {
            guard !groups.isEmpty else { continue }
            let rawURL = groups[0]
            let linkHTML = groups.count > 1 ? groups[1] : ""
            
            let chapterURL: String
            if rawURL.hasPrefix("http") {
                chapterURL = rawURL
            } else if rawURL.hasPrefix("/") {
                chapterURL = baseURL + rawURL
            } else if rawURL.hasPrefix("series/") {
                chapterURL = baseURL + "/" + rawURL
            } else {
                chapterURL = baseURL + "/series/" + rawURL
            }
            
            let numberPattern = "/chapter/(\\d+(?:\\.\\d+)?)"
            let chapterNumber: Double
            
            if let numStr = SourceEngineUtilities.firstMatch(in: chapterURL, pattern: numberPattern),
               let num = Double(numStr) {
                chapterNumber = num
            } else if !linkHTML.isEmpty,
                      let numStr = SourceEngineUtilities.firstMatch(in: linkHTML, pattern: "(\\d+(?:\\.\\d+)?)"),
                      let num = Double(numStr) {
                chapterNumber = num
            } else {
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
        debugLog("Returning \(sortedChapters.count) chapters from HTML")
        return SourceChapterDetails(chapters: sortedChapters)
    }
    
    // MARK: - Helper for parsing chapters from __NEXT_DATA__
    
    private func parseChaptersFromNextData(nextDataJSON: String, slug: String, mangaID: String) throws -> [Chapter] {
        guard let jsonData = nextDataJSON.data(using: .utf8) else {
            throw RuntimeSourceError.invalidResponse
        }
        
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
            debugLog("Invalid chapter URL: \(chapter.id)")
            throw RuntimeSourceError.chapterPagesMissing
        }
        
        debugLog("pages() for chapter: \(chapter.title)")
        debugLog("Chapter URL: \(url.absoluteString)")
        
        do {
            let html = try await getHTML(url: url, ttl: 60 * 30)
            
            debugLog("HTML length: \(html.count) characters")
            
            // Asura is a Next.js RSC (React Server Components) site.
            // Chapter page images are NOT rendered as <img> tags in the
            // initial HTML — they live inside serialized RSC / JSON payloads
            // in <script> tags with the structure:
            //   "pages":[{"order":1,"url":"https://gg.asuracomic.net/storage/media/426051/conversions/00-optimized.webp"}, ...]
            
            debugLog("Extracting chapter page URLs from RSC payload...")
            
            // Strategy 1: Find "pages":[...] array in the raw HTML/script data
            let pagesArrayPattern = #""pages"\s*:\s*\[(.*?)\]"#
            let pagesArrayMatches = SourceEngineUtilities.allMatches(
                in: html,
                pattern: pagesArrayPattern,
                options: [.dotMatchesLineSeparators]
            )
            debugLog("Found \(pagesArrayMatches.count) 'pages' arrays in payload")
            
            var bestPages: [(order: Int, url: String)] = []
            for pagesContent in pagesArrayMatches {
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
                debugLog("No chapter page URLs found in HTML")
                throw RuntimeSourceError.parserEmpty
            }
            
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
                    accentHex: SourceEngineUtilities.paletteColor(seed: "\(chapter.id)-\(index)"),
                    assetKind: .image,
                    assetPath: nil,
                    remoteURL: entry.url
                )
            }
            
            debugLog("Returning \(pages.count) pages")
            return SourcePageAsset(pages: pages, errorMessage: nil)
            
        } catch let error as RuntimeSourceError {
            debugLog("RuntimeSourceError: \(error)")
            throw error
        } catch {
            debugLog("Unexpected error: \(error)")
            throw RuntimeSourceError.invalidResponse
        }
    }

    func genreTags() async throws -> [GenreTag] { [] }

    // MARK: - Cookie/XSRF helpers

    private func xsrfToken() async -> String? {
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

    private func getHTML(url: URL, ttl: TimeInterval = 60 * 15) async throws -> String {
        await rateLimiter.waitTurn()
        let request = URLRequest(url: url)
        let key = SourceEngineUtilities.cacheKey(namespace: "asura-api-html", request: request)
        return try await SourceEngineUtilities.html(
            session: session,
            request: request,
            cacheKey: key,
            ttl: ttl
        )
    }

    private func getJSON(path: String, queryItems: [URLQueryItem] = [], ttl: TimeInterval = 60 * 10) async throws -> Data {
        var components = URLComponents(string: apiBaseURL + path)!
        components.queryItems = queryItems
        var request = URLRequest(url: components.url!)
        request.setValue(baseURL + "/", forHTTPHeaderField: "Referer")
        if let xsrf = await xsrfToken() {
            request.setValue(xsrf, forHTTPHeaderField: "x-xsrf-token")
        }
        await rateLimiter.waitTurn()
        let key = SourceEngineUtilities.cacheKey(namespace: "asura-api-json", request: request)
        return try await SourceEngineUtilities.data(
            session: session,
            request: request,
            cacheKey: key,
            ttl: ttl,
            cachePolicy: .returnCacheElseLoad,
            retryCount: 1,
            acceptedContentTypes: ["application/json", "text/json"]
        )
    }
}
