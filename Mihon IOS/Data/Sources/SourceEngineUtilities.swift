//
//  SourceEngineUtilities.swift
//  Mihon IOS
//

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
        slug.replacingOccurrences(of: "-", with: " ").capitalized
    }
}
