//
//  Routes.swift
//  Mihon IOS
//

import Foundation

enum LibraryRoute: Hashable {
    case mangaDetail(Manga)
    case reader(Manga, Chapter)
    case categoryManager
    case librarySettings
    case batchMigration
}

enum BrowseRoute: Hashable {
    case source(Source)
    case mangaDetail(Manga)
    case globalSearch
    case sourceCatalog
    case sourceCatalogDetail(SourceCatalogItem)
    case sourcePreferences(Source)
    case sourceRepos
    case sourceFilters
    case migrationSources
}

enum HistoryRoute: Hashable {
    case mangaDetail(Manga)
    case reader(Manga, Chapter)
}

enum UpdatesRoute: Hashable {
    case mangaDetail(Manga)
}

enum MoreRoute: Hashable {
    case downloadQueue
    case stats
    case settings
    case dataStorage
    case diagnostics
    case categories
    case about
    case backupCreate
    case backupRestore
    case tracking
}

