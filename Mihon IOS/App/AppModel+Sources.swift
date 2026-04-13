//
//  AppModel+Sources.swift
//  Mihon IOS
//

import Foundation

extension AppModel {
    var supportsAdultSources: Bool {
        sources.contains { $0.allowsAdultContent }
    }

    var visibleSources: [Source] {
        let preferredLanguageCodes = defaultCatalogLanguageCodes()
        let hideAdultSources = state.browsePreferences.hideAdultSources
        let enabledSourcesOnly = state.browsePreferences.enabledSourcesOnly
        let pinnedSourcesOnly = state.browsePreferences.pinnedSourcesOnly
        let enabledLanguages = state.browsePreferences.enabledLanguages

        sources.filter { source in
            let matchesLanguage: Bool
            if let code = descriptor(for: source.id)?.languageCode {
                matchesLanguage = preferredLanguageCodes.contains(normalizeLanguageCode(code))
            } else {
                matchesLanguage = enabledLanguages.contains(source.language)
            }

            return matchesLanguage &&
            (!hideAdultSources || !source.allowsAdultContent) &&
            (!enabledSourcesOnly || source.isEnabled) &&
            (!pinnedSourcesOnly || source.isPinned)
        }
    }

    var sourceDescriptors: [SourceDescriptor] {
        repository.descriptors()
    }

    func sourceCatalogItems() -> [SourceCatalogItem] {
        let builtInItems = [
            SourceCatalogItem(
                id: "official-json",
                title: "Official JSON Catalog",
                summary: "Primary source catalog metadata package for browse and source discovery on iOS.",
                version: "1.0.0",
                isInstalled: true,
                hasUpdate: false,
                isTrusted: true,
                languages: [.multi, .english],
                languageCodes: ["all", "multi", "en"],
                sources: visibleSources.filter { $0.kind == .remote && descriptor(for: $0.id)?.origin == "built-in" },
                originLabel: "Built-in",
                supportStatus: .live
            ),
            SourceCatalogItem(
                id: "local-tooling",
                title: "Local Import Toolkit",
                summary: "Local archive and folder importer for CBZ, ZIP, EPUB metadata, and image directories.",
                version: "1.1.0",
                isInstalled: true,
                hasUpdate: false,
                isTrusted: true,
                languages: [.multi],
                languageCodes: ["all", "multi"],
                sources: visibleSources.filter { $0.kind == .local },
                originLabel: "Built-in",
                supportStatus: .live
            ),
        ]

        let importedItems = repoRecords.flatMap { record in
            record.packages.map { package in
                let packageSources = package.sources.compactMap { imported in
                    resolvedSource(for: imported)
                }
                let packageStatus = package.sources.map(\.supportStatus).contains(.live)
                    ? SourceSupportStatus.live
                    : (package.sources.map(\.supportStatus).contains(.planned) ? .planned : .unsupported)
                return SourceCatalogItem(
                    id: "\(record.id)::\(package.id)",
                    title: package.name,
                    summary: record.lastError ?? "Imported from \(record.title) with \(package.sources.count) source(s).",
                    version: package.version,
                    isInstalled: true,
                    hasUpdate: false,
                    isTrusted: record.url.hasPrefix("https://"),
                    languages: Array(Set(package.sources.map(\.language))).sorted { $0.rawValue < $1.rawValue },
                    languageCodes: Array(Set(package.sources.map { normalizeLanguageCode($0.languageCode) })).sorted(),
                    sources: packageSources,
                    originLabel: record.title,
                    supportStatus: packageStatus
                )
            }
        }

        return builtInItems + importedItems
    }

    func sourcePreferences(for source: Source) -> [SourcePreference] {
        let descriptor = repository.descriptor(for: source.id)
        let importedCount = source.kind == .local ? "\(importRecords.count) imported title(s)" : "Catalog metadata"
        let languageValue = descriptor?.languageCode.map(languageFilterTitle(for:)) ?? source.language.rawValue
        return [
            SourcePreference(id: "\(source.id)-family", title: "Engine Family", value: source.engineFamily.title),
            SourcePreference(id: "\(source.id)-runtime", title: "Runtime", value: descriptor?.supportStatus.title ?? "Planned"),
            SourcePreference(id: "\(source.id)-lang", title: "Language", value: languageValue),
            SourcePreference(id: "\(source.id)-status", title: "Status", value: source.isEnabled ? "Enabled" : "Disabled"),
            SourcePreference(id: "\(source.id)-policy", title: "Adult Policy", value: source.allowsAdultContent ? "Allowed" : "Safe"),
            SourcePreference(id: "\(source.id)-imports", title: "Storage", value: importedCount),
            SourcePreference(id: "\(source.id)-caps", title: "Capabilities", value: descriptor.map { $0.capabilities.map(\.rawValue).sorted().joined(separator: ", ") } ?? "Unknown"),
            SourcePreference(id: "\(source.id)-origin", title: "Origin", value: descriptor?.origin ?? "Built-in"),
            SourcePreference(id: "\(source.id)-package", title: "Package", value: descriptor?.packageName ?? "N/A"),
            SourcePreference(id: "\(source.id)-version", title: "Version", value: descriptor?.version ?? "N/A"),
        ]
    }

    func addSourceRepo(_ url: String) async {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        importingRepoURL = trimmed
        defer { importingRepoURL = nil }

        do {
            let record = try await repoImporter.importRepo(from: trimmed)
            repoRecords.removeAll { $0.url == record.url }
            repoRecords.insert(record, at: 0)
            state.sourceRepos = repoRecords.map(\.url)
            repoImportErrorMessage = nil
            appendDiagnostic(
                kind: .repo,
                severity: .info,
                title: "Repo Imported",
                message: "Imported \(record.importedSources.count) source(s) from \(record.title).",
                errorCode: DiagnosticErrorCode.repoImported.rawValue,
                module: "Sources",
                metadata: [
                    "repo": record.title,
                    "importedSources": "\(record.importedSources.count)"
                ]
            )
            rebuildSourceRepository()
            persist()
        } catch {
            let failed = repoImporter.failedRecord(for: trimmed, error: error)
            repoRecords.removeAll { $0.url == failed.url }
            repoRecords.insert(failed, at: 0)
            state.sourceRepos = repoRecords.map(\.url)
            repoImportErrorMessage = failed.lastError
            appendDiagnostic(
                kind: .repo,
                severity: .error,
                title: "Repo Import Failed",
                message: failed.lastError ?? error.localizedDescription,
                errorCode: DiagnosticErrorCode.repoImportFailed.rawValue,
                module: "Sources",
                resolutionHint: "Check repository availability and validate manifest format.",
                metadata: ["repo": failed.title]
            )
            rebuildSourceRepository()
            persist()
        }
    }

    func refreshSourceRepo(_ url: String) async {
        guard let existing = repoRecords.first(where: { $0.url == url }) else {
            await addSourceRepo(url)
            return
        }

        importingRepoURL = existing.url
        defer { importingRepoURL = nil }

        let refreshed = await repoImporter.refresh(existing)
        repoRecords.removeAll { $0.url == existing.url }
        repoRecords.insert(refreshed, at: 0)
        state.sourceRepos = repoRecords.map(\.url)
        repoImportErrorMessage = refreshed.lastError
        appendDiagnostic(
            kind: .repo,
            severity: refreshed.lastError == nil ? .info : .error,
            title: refreshed.lastError == nil ? "Repo Refreshed" : "Repo Refresh Failed",
            message: refreshed.lastError ?? "Refreshed \(refreshed.importedSources.count) source(s) from \(refreshed.title).",
            errorCode: refreshed.lastError == nil
                ? DiagnosticErrorCode.repoRefreshed.rawValue
                : DiagnosticErrorCode.repoRefreshFailed.rawValue,
            module: "Sources",
            resolutionHint: refreshed.lastError == nil ? nil : "Retry refresh and verify repository endpoint.",
            metadata: [
                "repo": refreshed.title,
                "importedSources": "\(refreshed.importedSources.count)"
            ]
        )
        rebuildSourceRepository()
        persist()
    }

    func refreshAllSourceRepos() async {
        let urls = repoRecords.map(\.url)
        guard !urls.isEmpty else { return }
        repoImportErrorMessage = nil
        for url in urls {
            await refreshSourceRepo(url)
        }
    }

    func removeSourceRepo(_ url: String) {
        state.sourceRepos.removeAll { $0 == url }
        repoRecords.removeAll { $0.url == url }
        repoImportErrorMessage = nil
        appendDiagnostic(
            kind: .repo,
            severity: .info,
            title: "Repo Removed",
            message: "Removed source repository.",
            errorCode: DiagnosticErrorCode.repoRemoved.rawValue,
            module: "Sources",
            metadata: [:]
        )
        rebuildSourceRepository()
        persist()
    }

    func source(for id: String) -> Source? {
        sources.first { $0.id == id }
    }

    func primaryLocalSource() -> Source? {
        sources.first { $0.id == "local-files" } ?? sources.first(where: { $0.kind == .local })
    }

    func resolvedSourceOrNil(for sourceID: String) -> Source? {
        source(for: sourceID) ?? (sourceID == "local-files" ? primaryLocalSource() : nil)
    }

    func migrationSource(for manga: Manga) -> Source? {
        source(for: manga.sourceID) ?? sources.first(where: { $0.kind == .remote }) ?? primaryLocalSource()
    }

    func sourceWebURL(for source: Source, manga: Manga? = nil) -> URL? {
        if source.id == "kiryuu-id" {
            if let manga, let slug = manga.id.components(separatedBy: "::").last {
                return URL(string: "https://v1.kiryuu.to/manga/\(slug)/")
            }
            return URL(string: "https://v1.kiryuu.to")
        } else if source.id == "asura-en" {
            if let manga, let slug = manga.id.components(separatedBy: "::").last {
                return URL(string: "https://asuracomic.net/series/\(slug)/")
            }
            return URL(string: "https://asuracomic.net")
        }
        if let baseURL = descriptor(for: source.id)?.baseURL, let url = URL(string: baseURL) {
            return url
        }
        return URL(string: "https://mihon.app")
    }

    func supportsLiveSource(_ source: Source) -> Bool {
        guard let descriptor = repository.descriptor(for: source.id) else { return false }
        return source.kind == .remote && descriptor.supportStatus == .live
    }

    func supportsLiveSource(sourceID: String) -> Bool {
        sources.contains { $0.id == sourceID && supportsLiveSource($0) }
    }

    func descriptor(for sourceID: String) -> SourceDescriptor? {
        repository.descriptor(for: sourceID)
    }

    func globalSearchResults(query: String) -> [(Source, [Manga])] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        visibleSources.compactMap { source in
            let results = mangas(for: source).filter {
                $0.title.localizedCaseInsensitiveContains(trimmedQuery) ||
                $0.author.localizedCaseInsensitiveContains(trimmedQuery) ||
                $0.genres.joined(separator: " ").localizedCaseInsensitiveContains(trimmedQuery)
            }
            return results.isEmpty ? nil : (source, results)
        }
    }

    func defaultCatalogLanguageCodes() -> Set<String> {
        var languageCodes = Set<String>()
        for language in state.browsePreferences.enabledLanguages {
            languageCodes.formUnion(codes(for: language))
        }
        return languageCodes
    }

    func languageFilterTitle(for code: String) -> String {
        switch normalizeLanguageCode(code) {
        case "en": return "English"
        case "id": return "Indonesian"
        case "ja", "jp": return "Japanese"
        case "all", "multi": return "Multi"
        default: return code.uppercased()
        }
    }

    func sourceCatalogLanguageFilters() -> [(id: String, title: String)] {
        let codes = Set(sourceCatalogItems().flatMap(\.languageCodes).map(normalizeLanguageCode)).sorted()
        let dynamic = codes.map { (id: $0, title: languageFilterTitle(for: $0)) }
        return [("preferred", "Preferred"), ("all", "All")] + dynamic
    }

    func catalogItems(matchingLanguageFilter filterID: String) -> [SourceCatalogItem] {
        let items = sourceCatalogItems()
        switch filterID {
        case "all":
            return items
        case "preferred":
            let preferred = defaultCatalogLanguageCodes()
            return items.filter { item in
                item.languageCodes.isEmpty || !preferred.isDisjoint(with: Set(item.languageCodes.map(normalizeLanguageCode)))
            }
        default:
            let wanted = normalizeLanguageCode(filterID)
            return items.filter { item in
                item.languageCodes.contains(where: { normalizeLanguageCode($0) == wanted })
            }
        }
    }

    private func resolvedSource(for imported: ImportedSourceDescriptor) -> Source? {
        if let direct = sources.first(where: { $0.id == imported.sourceID }) {
            return direct
        }
        return sources.first { source in
            guard let descriptor = descriptor(for: source.id) else { return false }
            return descriptor.engineFamily == imported.engineFamily &&
                descriptor.baseURL?.caseInsensitiveCompare(imported.baseURL) == .orderedSame
        }
    }

    private func sourceMatchesBrowseLanguagePreferences(_ source: Source) -> Bool {
        if let code = descriptor(for: source.id)?.languageCode {
            return defaultCatalogLanguageCodes().contains(normalizeLanguageCode(code))
        }
        return state.browsePreferences.enabledLanguages.contains(source.language)
    }

    private func codes(for language: SourceLanguage) -> Set<String> {
        switch language {
        case .english:
            return ["en"]
        case .indonesian:
            return ["id"]
        case .japanese:
            return ["ja", "jp"]
        case .multi:
            return ["all", "multi"]
        }
    }

    private func normalizeLanguageCode(_ code: String) -> String {
        let lowered = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch lowered {
        case "jp":
            return "ja"
        default:
            return lowered
        }
    }
}
