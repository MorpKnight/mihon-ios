//
//  LocalImportRepository.swift
//  Mihon IOS
//

import Foundation
import ImageIO

struct ImportResult {
    let records: [ImportRecord]
    let jobs: [ImportJob]
    let failures: [ImportFailure]
}

struct ImportFailure: Identifiable, Hashable {
    let id = UUID()
    let fileName: String
    let reason: String
}

enum LocalImportError: LocalizedError {
    case duplicateItem(String)
    case emptyDirectory(String)
    case invalidImage(String)
    case unsupportedFile(String)

    var errorDescription: String? {
        switch self {
        case .duplicateItem(let name):
            return "\(name) is already imported."
        case .emptyDirectory(let name):
            return "\(name) does not contain readable image pages."
        case .invalidImage(let name):
            return "\(name) is not a readable image."
        case .unsupportedFile(let name):
            return "\(name) is not a supported import type."
        }
    }
}

final class FileImportRepository: ImportRepository {
    private let coordinator: FileDatabaseCoordinator
    private let fileManager: FileManager

    init(coordinator: FileDatabaseCoordinator, fileManager: FileManager = .default) {
        self.coordinator = coordinator
        self.fileManager = fileManager
    }

    func records() -> [ImportRecord] {
        coordinator.loadSnapshot().imports
    }

    func jobs() -> [ImportJob] {
        coordinator.loadSnapshot().importJobs
    }

    func importItems(from urls: [URL]) throws -> ImportResult {
        var snapshot = coordinator.loadSnapshot()
        let importedAt = Date()
        var failures: [ImportFailure] = []

        for url in urls {
            do {
                if snapshot.imports.contains(where: { $0.title.originalPath == url.path }) {
                    throw LocalImportError.duplicateItem(url.lastPathComponent)
                }
                let record = try makeRecord(from: url, importedAt: importedAt)
                snapshot.imports.removeAll { $0.id == record.id }
                snapshot.imports.insert(record, at: 0)

                let kind = record.title.kind
                let status: ImportStatus = switch kind {
                case .cbz, .zip, .epub: .pendingExtraction
                case .folder, .image: .ready
                case .unsupported: .failed
                }
                snapshot.importJobs.insert(
                    ImportJob(
                        id: UUID(),
                        fileName: url.lastPathComponent,
                        kind: kind,
                        status: status,
                        createdAt: importedAt,
                        importedTitleID: record.title.id,
                        detail: status == .ready ? "Imported into Local Files." : "Imported metadata. Archive extraction remains pending."
                    ),
                    at: 0
                )
            } catch {
                failures.append(
                    ImportFailure(
                        fileName: url.lastPathComponent,
                        reason: error.localizedDescription
                    )
                )
                snapshot.importJobs.insert(
                    ImportJob(
                        id: UUID(),
                        fileName: url.lastPathComponent,
                        kind: detectKind(url),
                        status: .failed,
                        createdAt: importedAt,
                        importedTitleID: nil,
                        detail: error.localizedDescription
                    ),
                    at: 0
                )
            }
        }

        snapshot.importJobs = Array(snapshot.importJobs.prefix(50))
        coordinator.saveSnapshot(snapshot)
        return ImportResult(records: snapshot.imports, jobs: snapshot.importJobs, failures: failures)
    }

    private func makeRecord(from url: URL, importedAt: Date) throws -> ImportRecord {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }

        let kind = detectKind(url)
        let titleID = "local-import-\(UUID().uuidString)"
        let titleDirectory = coordinator.importsDirectoryURL.appendingPathComponent(titleID, isDirectory: true)
        try fileManager.createDirectory(at: titleDirectory, withIntermediateDirectories: true, attributes: nil)

        switch kind {
        case .folder:
            return try importDirectory(url, titleID: titleID, destinationDirectory: titleDirectory, importedAt: importedAt)
        case .image:
            return try importSingleImage(url, titleID: titleID, destinationDirectory: titleDirectory, importedAt: importedAt)
        case .cbz, .zip, .epub:
            return try importArchiveStub(url, kind: kind, titleID: titleID, destinationDirectory: titleDirectory, importedAt: importedAt)
        case .unsupported:
            throw LocalImportError.unsupportedFile(url.lastPathComponent)
        }
    }

    private func importDirectory(_ url: URL, titleID: String, destinationDirectory: URL, importedAt: Date) throws -> ImportRecord {
        let children = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        let directories = children.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        let chapterSourceDirectories = directories.isEmpty ? [url] : directories
        var chapters: [ImportedChapter] = []
        var assets: [ImportedAsset] = []

        for (chapterIndex, chapterURL) in chapterSourceDirectories.enumerated() {
            let chapterID = "\(titleID)-chapter-\(chapterIndex + 1)"
            let chapterDestination = destinationDirectory.appendingPathComponent(chapterID, isDirectory: true)
            try fileManager.createDirectory(at: chapterDestination, withIntermediateDirectories: true, attributes: nil)

            let images = try imageFiles(in: chapterURL)
            guard !images.isEmpty else {
                if directories.isEmpty {
                    throw LocalImportError.emptyDirectory(url.lastPathComponent)
                }
                continue
            }
            var assetIDs: [String] = []

            for (imageIndex, imageURL) in images.enumerated() {
                let copiedURL = chapterDestination.appendingPathComponent(imageURL.lastPathComponent)
                if fileManager.fileExists(atPath: copiedURL.path) {
                    try? fileManager.removeItem(at: copiedURL)
                }
                try fileManager.copyItem(at: imageURL, to: copiedURL)

                let asset = ImportedAsset(
                    id: "\(chapterID)-asset-\(imageIndex + 1)",
                    chapterID: chapterID,
                    orderIndex: imageIndex,
                    kind: .image,
                    filePath: copiedURL.path,
                    textBody: nil,
                    accentHex: imageAccent(index: imageIndex)
                )
                assets.append(asset)
                assetIDs.append(asset.id)
            }

            chapters.append(
                ImportedChapter(
                    id: chapterID,
                    titleID: titleID,
                    title: directories.isEmpty ? "Chapter 1" : chapterURL.lastPathComponent,
                    orderIndex: chapterIndex,
                    assetIDs: assetIDs,
                    importedAt: importedAt
                )
            )
        }

        let coverPath = assets.first?.filePath
        guard !chapters.isEmpty, !assets.isEmpty else {
            throw LocalImportError.emptyDirectory(url.lastPathComponent)
        }
        let title = ImportedTitle(
            id: titleID,
            title: url.lastPathComponent,
            author: "Local Import",
            summary: "Imported from folder with \(chapters.count) chapter(s) and \(assets.count) page asset(s).",
            sourceID: "local-files",
            coverPath: coverPath,
            originalPath: url.path,
            kind: .folder,
            importedAt: importedAt,
            chapterIDs: chapters.map(\.id)
        )

        return ImportRecord(id: titleID, title: title, chapters: chapters, assets: assets)
    }

    private func importSingleImage(_ url: URL, titleID: String, destinationDirectory: URL, importedAt: Date) throws -> ImportRecord {
        let chapterID = "\(titleID)-chapter-1"
        let chapterDestination = destinationDirectory.appendingPathComponent(chapterID, isDirectory: true)
        try fileManager.createDirectory(at: chapterDestination, withIntermediateDirectories: true, attributes: nil)
        try validateImage(at: url)
        let copiedURL = chapterDestination.appendingPathComponent(url.lastPathComponent)
        if fileManager.fileExists(atPath: copiedURL.path) {
            try? fileManager.removeItem(at: copiedURL)
        }
        try fileManager.copyItem(at: url, to: copiedURL)

        let asset = ImportedAsset(
            id: "\(chapterID)-asset-1",
            chapterID: chapterID,
            orderIndex: 0,
            kind: .image,
            filePath: copiedURL.path,
            textBody: nil,
            accentHex: imageAccent(index: 0)
        )
        let chapter = ImportedChapter(
            id: chapterID,
            titleID: titleID,
            title: "Chapter 1",
            orderIndex: 0,
            assetIDs: [asset.id],
            importedAt: importedAt
        )
        let title = ImportedTitle(
            id: titleID,
            title: url.deletingPathExtension().lastPathComponent,
            author: "Local Import",
            summary: "Imported single-page local title.",
            sourceID: "local-files",
            coverPath: copiedURL.path,
            originalPath: url.path,
            kind: .image,
            importedAt: importedAt,
            chapterIDs: [chapter.id]
        )
        return ImportRecord(id: titleID, title: title, chapters: [chapter], assets: [asset])
    }

    private func importArchiveStub(_ url: URL, kind: ImportKind, titleID: String, destinationDirectory: URL, importedAt: Date) throws -> ImportRecord {
        let copiedURL = destinationDirectory.appendingPathComponent(url.lastPathComponent)
        if fileManager.fileExists(atPath: copiedURL.path) {
            try? fileManager.removeItem(at: copiedURL)
        }
        try fileManager.copyItem(at: url, to: copiedURL)

        let chapterID = "\(titleID)-chapter-1"
        let asset = ImportedAsset(
            id: "\(chapterID)-asset-1",
            chapterID: chapterID,
            orderIndex: 0,
            kind: .text,
            filePath: copiedURL.path,
            textBody: "Imported \(kind.rawValue.uppercased()) package. Metadata is stored and the title is now visible in Local Files, but archive extraction is still pending in this phase.",
            accentHex: "#3C8D7B"
        )
        let chapter = ImportedChapter(
            id: chapterID,
            titleID: titleID,
            title: "Imported Package",
            orderIndex: 0,
            assetIDs: [asset.id],
            importedAt: importedAt
        )
        let title = ImportedTitle(
            id: titleID,
            title: url.deletingPathExtension().lastPathComponent,
            author: "Local Import",
            summary: "Imported \(kind.rawValue.uppercased()) package. Extraction remains pending.",
            sourceID: "local-files",
            coverPath: nil,
            originalPath: url.path,
            kind: kind,
            importedAt: importedAt,
            chapterIDs: [chapter.id]
        )
        return ImportRecord(id: titleID, title: title, chapters: [chapter], assets: [asset])
    }

    private func imageFiles(in directory: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter { url in
                let ext = url.pathExtension.lowercased()
                return ["jpg", "jpeg", "png", "webp", "heic"].contains(ext)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func detectKind(_ url: URL) -> ImportKind {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return .folder
        }

        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "webp", "heic":
            return .image
        case "cbz":
            return .cbz
        case "zip":
            return .zip
        case "epub":
            return .epub
        default:
            return .unsupported
        }
    }

    private func imageAccent(index: Int) -> String {
        let palette = ["#5C8CFF", "#3C8D7B", "#7A5CFF", "#D56F3E", "#2D79C7"]
        return palette[index % palette.count]
    }

    private func validateImage(at url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw LocalImportError.invalidImage(url.lastPathComponent)
        }
    }
}

final class DefaultLocalContentRepository: LocalContentRepository {
    func mangas(from records: [ImportRecord], sourceID: String) -> [Manga] {
        records.map { record in
            Manga(
                id: record.title.id,
                sourceID: sourceID,
                title: record.title.title,
                author: record.title.author,
                summary: record.title.summary,
                genres: ["Local", record.title.kind.rawValue.uppercased()],
                coverHexes: ["#3C8D7B", "#162B27"],
                coverURL: nil,
                statusText: "Local"
            )
        }
        .sorted { $0.title < $1.title }
    }

    func chapters(for mangaID: String, from records: [ImportRecord]) -> [Chapter] {
        guard let record = records.first(where: { $0.title.id == mangaID }) else { return [] }
        return record.chapters
            .sorted { $0.orderIndex > $1.orderIndex }
            .map { chapter in
                let pages = record.assets
                    .filter { $0.chapterID == chapter.id }
                    .sorted { $0.orderIndex < $1.orderIndex }
                    .enumerated()
                    .map { index, asset in
                        ReaderPage(
                            id: asset.id,
                            index: index,
                            title: "Page \(index + 1)",
                            body: asset.textBody ?? "Imported local asset",
                            accentHex: asset.accentHex,
                            assetKind: asset.kind,
                            assetPath: asset.filePath,
                            remoteURL: nil
                        )
                    }
                return Chapter(
                    id: chapter.id,
                    mangaID: mangaID,
                    title: chapter.title,
                    number: Double(record.chapters.count - chapter.orderIndex),
                    releaseDate: chapter.importedAt,
                    isDownloaded: true,
                    pages: pages
                )
            }
    }
}

struct DefaultReaderAssetRepository: ReaderAssetRepository {
    func fileURL(for page: ReaderPage) -> URL? {
        guard let assetPath = page.assetPath else { return nil }
        return URL(fileURLWithPath: assetPath)
    }
}
