//
//  AppModel+DiagnosticsAndCache.swift
//  Mihon IOS
//

import Foundation

extension AppModel {
    enum DiagnosticsExportFormat {
        case json
        case csv

        var fileExtension: String {
            switch self {
            case .json:
                return "json"
            case .csv:
                return "csv"
            }
        }
    }

    func statsSections() -> [StatsSection] {
        let recentHistory = historyDisplayEntries
        let uniqueReadTitles = Set(state.history.map(\.mangaID)).count
        let latestHistory = recentHistory.first
        let latestProgress = state.progress
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
        let latestProgressTitle = latestProgress.flatMap { progress in
            allManga.first(where: { $0.id == progress.mangaID }).map { manga in
                let chapterTitle = progress.chapterTitle ?? chapter(for: progress.chapterID, in: manga)?.title ?? "Chapter"
                return StatsItem(
                    title: "Last Progress Update",
                    value: manga.title,
                    systemImage: "bookmark",
                    detail: "\(chapterTitle) • Page \(progress.pageIndex + 1) of \(max(progress.totalPages, 1))"
                )
            }
        }

        var sections: [StatsSection] = [
            StatsSection(
                title: "Overview",
                items: [
                    StatsItem(title: "Library Titles", value: "\(state.library.count)", systemImage: "books.vertical"),
                    StatsItem(title: "Titles In Progress", value: "\(state.progress.count)", systemImage: "book"),
                    StatsItem(title: "History Entries", value: "\(state.history.count)", systemImage: "clock.arrow.circlepath"),
                    StatsItem(title: "Tracked Titles", value: "\(state.trackers.count)", systemImage: "person.badge.clock"),
                    StatsItem(title: "Imported Titles", value: "\(importRecords.count)", systemImage: "tray.and.arrow.down"),
                    StatsItem(title: "Categories", value: "\(state.categories.count)", systemImage: "folder")
                ]
            ),
            StatsSection(
                title: "Reading Activity",
                items: [
                    StatsItem(title: "Titles Opened", value: "\(uniqueReadTitles)", systemImage: "text.book.closed"),
                    latestHistory.map { entry, manga, chapter in
                        StatsItem(
                            title: "Last Opened Chapter",
                            value: manga.title,
                            systemImage: "clock.badge.checkmark",
                            detail: "\(chapter.title) • \(entry.timestamp.formatted(date: .abbreviated, time: .shortened))"
                        )
                    },
                    latestProgressTitle
                ].compactMap { $0 }
            )
        ]

        let recentTitles = recentHistory.reduce(into: [StatsItem]()) { partial, item in
            guard partial.count < 3 else { return }
            let (_, manga, chapter) = item
            guard partial.contains(where: { $0.value == manga.title }) == false else { return }
            partial.append(
                StatsItem(
                    title: chapter.title,
                    value: manga.title,
                    systemImage: "clock",
                    detail: item.0.timestamp.formatted(date: .abbreviated, time: .shortened)
                )
            )
        }

        if !recentTitles.isEmpty {
            sections.append(StatsSection(title: "Recent Titles", items: recentTitles))
        }

        return sections.filter { !$0.items.isEmpty }
    }

    var hasMeaningfulStats: Bool {
        !state.library.isEmpty || !state.progress.isEmpty || !state.history.isEmpty || !state.trackers.isEmpty || !importRecords.isEmpty
    }

    func diagnosticsSummary() -> [String] {
        let criticalCount = diagnosticLogs.filter { $0.severity == .critical }.count
        let errorCount = diagnosticLogs.filter { $0.severity == .error }.count
        let warningCount = diagnosticLogs.filter { $0.severity == .warning }.count
        let infoCount = diagnosticLogs.filter { $0.severity == .info }.count

        return [
            "Schema v\(state.schemaVersion)",
            "Sources: \(visibleSources.count)/\(sources.count)",
            "Source repos: \(state.sourceRepos.count)",
            "Page cache: \(pageCache.count)",
            "Chapter cache: \(chapterCache.count)",
            "Disk image cache: \(formatBytes(cacheStats.diskImageBytes))",
            "Disk metadata cache: \(formatBytes(cacheStats.diskMetadataBytes))",
            "Cache hits/misses: \(cacheStats.hitCount)/\(cacheStats.missCount)",
            "Error logs: \(diagnosticLogs.count)",
            "Source errors: \(sourceErrors.count)",
            "Page load errors: \(pageLoadErrors.count)",
            "Severity (C/E/W/I): \(criticalCount)/\(errorCount)/\(warningCount)/\(infoCount)",
        ]
    }

    func filteredDiagnostics(
        kind: DiagnosticLogKind? = nil,
        severity: DiagnosticSeverity? = nil,
        dateRange: ClosedRange<Date>? = nil,
        query: String = ""
    ) -> [DiagnosticLogEntry] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return diagnosticLogs.filter { entry in
            if let kind, entry.kind != kind {
                return false
            }

            if let severity, entry.severity != severity {
                return false
            }

            if let dateRange, !dateRange.contains(entry.timestamp) {
                return false
            }

            guard !normalizedQuery.isEmpty else {
                return true
            }

            if entry.title.lowercased().contains(normalizedQuery) || entry.message.lowercased().contains(normalizedQuery) {
                return true
            }

            return entry.metadata.contains { key, value in
                key.lowercased().contains(normalizedQuery) || value.lowercased().contains(normalizedQuery)
            }
        }
    }

    func exportDiagnosticsJSON(entries: [DiagnosticLogEntry]? = nil) -> String {
        let exportEntries = entries ?? diagnosticLogs
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(exportEntries), let output = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return output
    }

    func exportDiagnosticsCSV(entries: [DiagnosticLogEntry]? = nil) -> String {
        let exportEntries = entries ?? diagnosticLogs
        let header = [
            "timestamp",
            "severity",
            "kind",
            "title",
            "message",
            "errorCode",
            "module",
            "resolutionHint",
            "metadata"
        ]

        let rows = exportEntries.map { entry in
            let metadata = entry.metadata
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "; ")

            return [
                entry.timestamp.formatted(.iso8601),
                entry.severity.rawValue,
                entry.kind.rawValue,
                entry.title,
                entry.message,
                entry.errorCode ?? "",
                entry.module ?? "",
                entry.resolutionHint ?? "",
                metadata
            ]
            .map(csvEscaped)
            .joined(separator: ",")
        }

        return ([header.joined(separator: ",")] + rows).joined(separator: "\n")
    }

    func diagnosticsExportFileURL(format: DiagnosticsExportFormat, entries: [DiagnosticLogEntry]? = nil) -> URL? {
        let content: String
        switch format {
        case .json:
            content = exportDiagnosticsJSON(entries: entries)
        case .csv:
            content = exportDiagnosticsCSV(entries: entries)
        }

        let fileName = "mihon-diagnostics-\(Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))).\(format.fileExtension)"
        let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try content.write(to: temporaryURL, atomically: true, encoding: .utf8)
            return temporaryURL
        } catch {
            return nil
        }
    }

    func clearDiagnostics() {
        diagnosticLogs.removeAll()
        persist()
    }

    func clearImageCache() async {
        await ReaderImagePipeline.shared.clear()
        await refreshCacheStats()
    }

    func clearSourceMetadataCache() async {
        await cacheController.clear(.sourceMetadata)
        clearCachedGenreTags()
        clearCachedSourceManga()
        clearCachedChapters(preservingOfflineOnly: true)
        clearCachedPages()
        appendDiagnostic(
            kind: .cache,
            severity: .info,
            title: "Metadata Cache Cleared",
            message: "Source metadata caches were cleared.",
            errorCode: DiagnosticErrorCode.cacheMetadataCleared.rawValue,
            module: "DiagnosticsAndCache",
            metadata: [:]
        )
        await refreshCacheStats()
    }

    func clearAllCaches() async {
        await cacheController.clear(.all)
        clearCachedGenreTags()
        clearCachedSourceManga()
        clearCachedChapters(preservingOfflineOnly: true)
        clearCachedPages()
        appendDiagnostic(
            kind: .cache,
            severity: .info,
            title: "All Caches Cleared",
            message: "Image and metadata caches were cleared.",
            errorCode: DiagnosticErrorCode.cacheAllCleared.rawValue,
            module: "DiagnosticsAndCache",
            metadata: [:]
        )
        await refreshCacheStats()
    }

    func respondToMemoryPressure() {
        trimRuntimeCaches(fraction: 0.5)

        Task {
            await cacheController.trimMemory(fraction: 0.5)
            await refreshCacheStats()
        }

        appendDiagnostic(
            kind: .cache,
            severity: .warning,
            title: "Memory Pressure Response",
            message: "Trimmed in-memory caches by 50%.",
            errorCode: DiagnosticErrorCode.cacheMemoryPressureTrim.rawValue,
            module: "DiagnosticsAndCache",
            metadata: [
                "pageCache": "\(pageCache.count)",
                "sourceMangaCache": "\(sourceMangaCache.count)",
                "chapterCache": "\(chapterCache.count)",
            ]
        )
    }

    private func formatBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func csvEscaped(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

struct StatsItem: Identifiable, Hashable {
    var id: String { title }
    let title: String
    let value: String
    let systemImage: String
    var detail: String? = nil
}

struct StatsSection: Identifiable, Hashable {
    var id: String { title }
    let title: String
    let items: [StatsItem]
}
