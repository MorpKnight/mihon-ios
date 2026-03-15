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

    static func mapSeriesList(html: String, sourceID: String) -> [Manga] {
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
            let title = SourceEngineUtilities.titleFromSlug(slug)
            let manga = Manga(
                id: "\(sourceID)::\(slug)",
                sourceID: sourceID,
                title: title,
                author: "Unknown",
                summary: "Imported from Asura listing.",
                genres: ["Manhwa"],
                coverHexes: SourceEngineUtilities.palette(for: slug),
                coverURL: nil,
                statusText: "Unknown"
            )
            items.append(manga)
        }
        return items
    }
}
