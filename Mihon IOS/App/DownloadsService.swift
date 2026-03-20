//
//  DownloadsService.swift
//  Mihon IOS
//

import Foundation

protocol DownloadsServicing {
    func downloadAndStorePages(
        pages: [ReaderPage],
        chapterBaseDirectory: URL,
        chapterComponent: String,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> [ReaderPage]
}

final class DefaultDownloadsService: DownloadsServicing {
    func downloadAndStorePages(
        pages: [ReaderPage],
        chapterBaseDirectory: URL,
        chapterComponent: String,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> [ReaderPage] {
        try FileManager.default.createDirectory(at: chapterBaseDirectory, withIntermediateDirectories: true, attributes: nil)

        let partial = chapterBaseDirectory.appendingPathComponent("\(chapterComponent).partial", isDirectory: true)
        let committed = chapterBaseDirectory.appendingPathComponent(chapterComponent, isDirectory: true)
        try? FileManager.default.removeItem(at: partial)
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true, attributes: nil)

        let imagePages = pages.filter { $0.assetKind == .image }
        let total = max(imagePages.count, 1)
        var completedCount = 0

        var updated: [ReaderPage] = []
        updated.reserveCapacity(pages.count)

        for page in pages {
            if Task.isCancelled { throw CancellationError() }
            if page.assetKind != .image {
                updated.append(page)
                continue
            }

            guard let remote = page.remoteURL, let url = URL(string: remote) else {
                throw NSError(domain: "Downloads", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing page URL."])
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                throw URLError(.badServerResponse)
            }

            let ext = url.pathExtension.isEmpty ? "img" : url.pathExtension
            let fileURL = partial.appendingPathComponent("page_\(page.index).\(ext)")
            try data.write(to: fileURL, options: .atomic)

            let newPage = ReaderPage(
                id: page.id,
                index: page.index,
                title: page.title,
                body: page.body,
                accentHex: page.accentHex,
                assetKind: page.assetKind,
                assetPath: fileURL.path,
                remoteURL: page.remoteURL
            )
            updated.append(newPage)

            completedCount += 1
            let value = Double(completedCount) / Double(total)
            await progress(min(max(value, 0), 1))
        }

        try? FileManager.default.removeItem(at: committed)
        try FileManager.default.moveItem(at: partial, to: committed)

        return updated.map { page in
            guard let assetPath = page.assetPath else { return page }
            let partialPrefix = partial.path + "/"
            let finalPath: String
            if assetPath.hasPrefix(partialPrefix) {
                finalPath = committed.path + "/" + assetPath.dropFirst(partialPrefix.count)
            } else {
                finalPath = assetPath.replacingOccurrences(of: ".partial/", with: "/")
            }

            return ReaderPage(
                id: page.id,
                index: page.index,
                title: page.title,
                body: page.body,
                accentHex: page.accentHex,
                assetKind: page.assetKind,
                assetPath: finalPath,
                remoteURL: page.remoteURL
            )
        }
    }
}
