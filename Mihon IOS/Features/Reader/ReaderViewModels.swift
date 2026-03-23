//
//  ReaderViewModels.swift
//  Mihon IOS
//

import Foundation

enum ReaderPagerItem: Identifiable {
    case previousChapter
    case render(ReaderRenderItem)
    case nextChapter

    var id: String {
        switch self {
        case .previousChapter:
            return "transition-previous"
        case .render(let item):
            return item.id
        case .nextChapter:
            return "transition-next"
        }
    }
}

enum ReaderContentLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed
}

struct ReaderPageActionContext: Identifiable {
    let id: String
    let chapterTitle: String
    let pageTitle: String
    let page: ReaderPage
    let remoteURL: URL?
    let localFileURL: URL?
}

struct ReaderTransitionRecoveryContext {
    let chapter: Chapter
    let pageIndex: Int
    let snapshot: ReaderContentSnapshot?
}
