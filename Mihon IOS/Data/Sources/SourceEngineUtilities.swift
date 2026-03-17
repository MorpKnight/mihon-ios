//
//  SourceEngineUtilities.swift
//  Mihon IOS
//

import CryptoKit
import Foundation

// MARK: - Shared Error Type

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

// MARK: - Rate Limiter

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

// MARK: - Shared Utility Functions

enum SourceEngineUtilities {

    static let defaultUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1 Mihon-iOS/1.0"
    static let sharedURLCache = URLCache(
        memoryCapacity: 48 * 1_024 * 1_024,
        diskCapacity: 160 * 1_024 * 1_024
    )

    static func sessionConfiguration(additionalHeaders: [String: String]) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.requestCachePolicy = .useProtocolCachePolicy
        config.urlCache = sharedURLCache
        config.httpMaximumConnectionsPerHost = 6
        config.httpAdditionalHeaders = additionalHeaders
        return config
    }

    static func cacheKey(namespace: String, request: URLRequest, suffix: String? = nil) -> String {
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? "unknown"
        let bodyDigest: String
        if let body = request.httpBody, !body.isEmpty {
            bodyDigest = digest(body)
        } else {
            bodyDigest = "no-body"
        }
        if let suffix, !suffix.isEmpty {
            return "\(namespace)|\(method)|\(url)|\(bodyDigest)|\(suffix)"
        }
        return "\(namespace)|\(method)|\(url)|\(bodyDigest)"
    }

    static func data(
        session: URLSession,
        request: URLRequest,
        cacheKey: String,
        ttl: TimeInterval,
        cachePolicy: CachePolicy = .returnCacheElseLoad,
        retryCount: Int = 1,
        acceptedContentTypes: [String] = [],
        validateResponse: Bool = true
    ) async throws -> Data {
        try await AppCacheController.shared.data(
            for: cacheKey,
            domain: .networkResponse,
            policy: cachePolicy,
            ttl: ttl
        ) {
            try await loadData(
                session: session,
                request: request,
                retryCount: retryCount,
                acceptedContentTypes: acceptedContentTypes,
                validateResponse: validateResponse
            )
        }
    }

    static func html(
        session: URLSession,
        request: URLRequest,
        cacheKey: String,
        ttl: TimeInterval,
        cachePolicy: CachePolicy = .returnCacheElseLoad
    ) async throws -> String {
        let data = try await data(
            session: session,
            request: request,
            cacheKey: cacheKey,
            ttl: ttl,
            cachePolicy: cachePolicy,
            retryCount: 1
        )
        guard let html = String(data: data, encoding: .utf8) else {
            throw RuntimeSourceError.invalidResponse
        }
        return html
    }

    static func stripHTML(_ html: String) -> String {
        let withoutTags = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return decodeHTML(withoutTags)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    static func firstMatch(in text: String, pattern: String, options: NSRegularExpression.Options = []) -> String? {
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

    static func allMatches(in text: String, pattern: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> [String] {
        let regex = try? NSRegularExpression(pattern: pattern, options: options)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex?.matches(in: text, range: range) ?? []
        return matches.compactMap { match in
            guard let capture = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[capture])
        }
    }

    static func allMatchesWithGroups(in text: String, pattern: String, groupCount: Int) -> [[String]] {
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

    static func palette(for seed: String) -> [String] {
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

    static func paletteColor(seed: String) -> String {
        palette(for: seed).first ?? "#2563EB"
    }

    static func slug(from idOrURL: String) -> String {
        if let url = URL(string: idOrURL), url.host != nil {
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.count >= 2, parts[0] == "series" { return parts[1] }
        }
        let parts = idOrURL.components(separatedBy: "::")
        return parts.last ?? idOrURL
    }

    static func titleFromSlug(_ slug: String) -> String {
        // Strip trailing hash suffixes common in Asura slugs (e.g. "my-title-90358a23")
        let cleaned = slug.replacingOccurrences(
            of: #"-[0-9a-f]{6,10}$"#,
            with: "",
            options: .regularExpression
        )
        return cleaned.replacingOccurrences(of: "-", with: " ").capitalized
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func loadData(
        session: URLSession,
        request: URLRequest,
        retryCount: Int,
        acceptedContentTypes: [String],
        validateResponse: Bool
    ) async throws -> Data {
        var attempts = 0
        var lastError: Error?

        while attempts <= retryCount {
            do {
                let (data, response) = try await session.data(for: request)
                if validateResponse {
                    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                        throw RuntimeSourceError.invalidResponse
                    }
                    if !acceptedContentTypes.isEmpty,
                       let contentType = http.value(forHTTPHeaderField: "Content-Type"),
                       !acceptedContentTypes.contains(where: { contentType.localizedCaseInsensitiveContains($0) }) {
                        throw RuntimeSourceError.invalidResponse
                    }
                }
                return data
            } catch {
                lastError = error
                attempts += 1
                if attempts <= retryCount {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
            }
        }

        throw lastError ?? RuntimeSourceError.invalidResponse
    }
}
