//
//  ReaderView.swift
//  Mihon IOS
//

import SwiftUI
import UIKit

struct ReaderView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    let manga: Manga
    let initialChapter: Chapter

    @State private var currentChapter: Chapter
    @State private var pageIndex: Int
    @State private var showingSettings = false
    @State private var showingActions = false
    @State private var showingChrome = false
    @State private var pageLoadState: ReaderContentLoadState = .idle
    @State private var retryTick = 0
    @State private var pendingPageIndexAfterChapterChange: Int?
    @State private var activeLoadRequestID = UUID()
    @State private var prefetchTask: Task<Void, Never>?
    @State private var hasAppliedResumeProgress = false
    @State private var canPersistPageProgress = false
    @State private var pagerDisplayIndex = 1

    private let verticalScrollCoordinateSpace = "reader.vertical.scroll"

    init(manga: Manga, initialChapter: Chapter) {
        self.manga = manga
        self.initialChapter = initialChapter
        _currentChapter = State(initialValue: initialChapter)
        _pageIndex = State(initialValue: 0)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geometry in
                readerBody
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                handleTap(atX: value.location.x, width: geometry.size.width)
                            }
                    )
            }

            if showingChrome {
                readerChrome
                    .transition(.opacity)
            }
        }
        .simultaneousGesture(backSwipeGesture)
        .background(Color.black)
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .statusBarHidden(!showingChrome)
        .sheet(isPresented: $showingSettings) {
            ReaderSettingsView()
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Page Actions", isPresented: $showingActions, titleVisibility: .visible) {
            ShareLink(item: "\(manga.title) • \(currentChapter.title)") {
                Label("Share Chapter", systemImage: "square.and.arrow.up")
            }
            Button("Copy Chapter Title") { }
            Button("Close", role: .cancel) { }
        }
        .onAppear {
            canPersistPageProgress = false
            if let progress = model.progress(for: manga), progress.chapterID == currentChapter.id {
                pendingPageIndexAfterChapterChange = max(progress.pageIndex, 0)
            }
            startPageLoad(forceRefresh: false)
        }
        .onChange(of: pageIndex) { _, newValue in
            guard !currentPages.isEmpty else { return }
            let boundedPageIndex = boundedPageIndex(for: newValue)
            if boundedPageIndex != newValue {
                pageIndex = boundedPageIndex
                return
            }
            prefetchAroundCurrentPage()
            guard canPersistPageProgress, pageLoadState == .loaded else { return }
            persistProgress()
        }
        .onChange(of: currentChapter.id) { _, _ in
            canPersistPageProgress = false
            pageIndex = pendingPageIndexAfterChapterChange ?? 0
            hasAppliedResumeProgress = false
            startPageLoad(forceRefresh: false)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, canPersistPageProgress, !currentPages.isEmpty { persistProgress() }
        }
        .onDisappear {
            activeLoadRequestID = UUID()
            prefetchTask?.cancel()
            prefetchTask = nil
            Task {
                await ReaderImagePipeline.shared.cancelPrefetch(for: currentChapter.id)
            }
        }
    }

    private var backSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                guard isVerticalReader else { return }
                guard value.startLocation.x <= 28 else { return }
                guard value.translation.width > 90 else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dismiss()
            }
    }

    @ViewBuilder
    private var readerBody: some View {
        if pageLoadState == .loading && currentPages.isEmpty {
            ProgressView("Loading chapter…")
                .tint(.white)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
        } else if currentPages.isEmpty {
            ReaderEmptyState(
                message: model.pageLoadError(for: currentChapter.id) ?? "No readable pages were found for this chapter.",
                retry: {
                    startPageLoad(forceRefresh: true)
                }
            )
        } else if model.state.readerPreferences.mode == .vertical || model.state.readerPreferences.mode == .webtoon {
            GeometryReader { scrollGeometry in
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: model.state.readerPreferences.mode == .webtoon ? 0 : 12) {
                            ForEach(Array(currentPages.enumerated()), id: \.element.id) { offset, page in
                                ReaderPageSurface(
                                    page: page,
                                    filter: model.state.readerPreferences.colorFilter,
                                    fillViewport: false,
                                    allowsImagePan: false
                                )
                                    .id(pageAnchorID(for: offset))
                                    .background(
                                        GeometryReader { proxy in
                                            Color.clear.preference(
                                                key: ReaderVisiblePageFramesPreferenceKey.self,
                                                value: [offset: proxy.frame(in: .named(verticalScrollCoordinateSpace))]
                                            )
                                        }
                                    )
                            }
                        }
                        .padding(.vertical, model.state.readerPreferences.mode == .webtoon ? 0 : 12)
                    }
                    .coordinateSpace(name: verticalScrollCoordinateSpace)
                    .ignoresSafeArea()
                    .simultaneousGesture(verticalBoundaryGesture)
                    .onPreferenceChange(ReaderVisiblePageFramesPreferenceKey.self) { frames in
                        updateVerticalPageIndex(from: frames, viewportHeight: scrollGeometry.size.height)
                    }
                    .onChange(of: currentChapter.id) { _, _ in
                        scrollToCurrentPage(using: scrollProxy, animated: false)
                    }
                    .onChange(of: retryTick) { _, _ in
                        scrollToCurrentPage(using: scrollProxy, animated: false)
                    }
                    .onChange(of: pageLoadState) { _, newState in
                        guard newState == .loaded else { return }
                        scrollToCurrentPage(using: scrollProxy, animated: false)
                    }
                }
            }
        } else {
            GeometryReader { geometry in
                pagedReaderBody(width: geometry.size.width)
            }
            .ignoresSafeArea()
        }
    }

    private func pagedReaderBody(width: CGFloat) -> some View {
        let pageWidth = max(width, 1)
        return ReaderPagedContainer(
            currentIndex: $pagerDisplayIndex,
            itemCount: pagerItems.count,
            canMoveBackward: pagerDisplayIndex > 0,
            canMoveForward: pagerDisplayIndex < max(pagerItems.count - 1, 0),
            onPageChanged: { newIndex in
                handlePagerDisplayIndexChange(newIndex)
            },
            onBoundaryAdvance: { translation in
                handlePagerBoundaryAdvance(translationWidth: translation)
            }
        ) {
            HStack(spacing: 0) {
                ForEach(Array(pagerItems.enumerated()), id: \.element.id) { _, item in
                    Group {
                        switch item {
                        case .page(let page):
                            ReaderPageSurface(
                                page: page,
                                filter: model.state.readerPreferences.colorFilter,
                                fillViewport: true,
                                allowsImagePan: true
                            )
                        case .previousChapter:
                            ReaderTransitionPage(
                                title: "Previous Chapter",
                                chapterTitle: previousChapterForCurrentMode()?.title,
                                systemImage: chapterLeadingIcon,
                                isEnabled: previousChapterForCurrentMode() != nil
                            )
                        case .nextChapter:
                            ReaderTransitionPage(
                                title: "Next Chapter",
                                chapterTitle: nextChapterForCurrentMode()?.title,
                                systemImage: chapterTrailingIcon,
                                isEnabled: nextChapterForCurrentMode() != nil
                            )
                        }
                    }
                    .frame(width: pageWidth)
                    .ignoresSafeArea()
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            syncPagerDisplayIndex(animated: false)
        }
        .onChange(of: pageIndex) { _, _ in
            syncPagerDisplayIndex(animated: true)
        }
        .onChange(of: currentChapter.id) { _, _ in
            syncPagerDisplayIndex(animated: false)
        }
        .onChange(of: model.state.readerPreferences.mode) { _, _ in
            syncPagerDisplayIndex(animated: false)
        }
    }

    private var verticalBoundaryGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                guard isVerticalReader else { return }
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                if value.translation.height > 120, pageIndex == 0, let chapter = previousChapterForCurrentMode() {
                    transitionToChapter(chapter, pageIndex: lastPageIndex(for: chapter))
                } else if value.translation.height < -120, pageIndex >= max(currentPages.count - 1, 0), let chapter = nextChapterForCurrentMode() {
                    transitionToChapter(chapter, pageIndex: 0)
                }
            }
    }

    private var readerChrome: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            VStack(spacing: 12) {
                chapterNavigator
                bottomBar
            }
            .padding(.bottom, 8)
        }
        .animation(.easeInOut(duration: 0.18), value: showingChrome)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(manga.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(currentChapter.title)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(1)
            }

            Spacer()

            Button {
                showingActions = true
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
            }

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .background(readerBarBackground)
    }

    private var chapterNavigator: some View {
        let total = max(currentPages.count, 1)
        return HStack(spacing: 12) {
            Button {
                if let chapter = previousChapterForCurrentMode() {
                    transitionToChapter(chapter, pageIndex: lastPageIndex(for: chapter))
                }
            } label: {
                Image(systemName: chapterLeadingIcon)
                    .font(.headline)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .background(readerCapsuleBackground, in: Circle())
            .foregroundStyle(.white)
            .disabled(previousChapterForCurrentMode() == nil)
            .opacity(previousChapterForCurrentMode() == nil ? 0.35 : 1)

            HStack(spacing: 12) {
                Text("\(pageIndex + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(minWidth: 22, alignment: .trailing)

                if total > 1 {
                    Slider(
                        value: Binding(
                            get: { Double(pageIndex + 1) },
                            set: { value in
                                let newIndex = max(0, min(total - 1, Int(value.rounded()) - 1))
                                if newIndex != pageIndex {
                                    pageIndex = newIndex
                                }
                            }
                        ),
                        in: 1...Double(total),
                        step: 1
                    )
                    .tint(.white)
                } else {
                    Capsule()
                        .fill(Color.white.opacity(0.16))
                        .frame(height: 4)
                }

                Text("\(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(minWidth: 22, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(readerCapsuleBackground, in: Capsule())

            Button {
                if let chapter = nextChapterForCurrentMode() {
                    transitionToChapter(chapter, pageIndex: 0)
                }
            } label: {
                Image(systemName: chapterTrailingIcon)
                    .font(.headline)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .background(readerCapsuleBackground, in: Circle())
            .foregroundStyle(.white)
            .disabled(nextChapterForCurrentMode() == nil)
            .opacity(nextChapterForCurrentMode() == nil ? 0.35 : 1)
        }
        .padding(.horizontal, 12)
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            ReaderBottomPill(
                systemImage: readingModeSymbol,
                title: model.state.readerPreferences.mode.title,
                isProminent: true
            ) {
                cycleReadingMode()
            }

            ReaderBottomPill(systemImage: orientationSymbol, title: model.state.readerPreferences.orientation.rawValue.capitalized) {
                cycleOrientation()
            }

            ReaderBottomPill(
                systemImage: model.state.readerPreferences.showPageNumber ? "number.circle.fill" : "number.circle",
                title: "Page"
            ) {
                model.setReaderPageNumberVisible(!model.state.readerPreferences.showPageNumber)
            }

            ReaderBottomPill(systemImage: "slider.horizontal.3", title: "Settings") {
                showingSettings = true
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 12)
    }

    private var currentPages: [ReaderPage] {
        let resolved = model.resolvedChapter(currentChapter)
        return resolved.pages.isEmpty ? currentChapter.pages : resolved.pages
    }

    private var currentChapterResumeProgress: ReadingProgress? {
        guard let progress = model.progress(for: manga), progress.chapterID == currentChapter.id else {
            return nil
        }
        return progress
    }

    private var isVerticalReader: Bool {
        model.state.readerPreferences.mode == .vertical || model.state.readerPreferences.mode == .webtoon
    }

    private var pagerPages: [ReaderPage] {
        isRTLPager ? currentPages.reversed() : currentPages
    }

    private var pagerItems: [ReaderPagerItem] {
        var items: [ReaderPagerItem] = []
        if isRTLPager {
            items.append(.nextChapter)
            items.append(contentsOf: pagerPages.map(ReaderPagerItem.page))
            items.append(.previousChapter)
        } else {
            items.append(.previousChapter)
            items.append(contentsOf: pagerPages.map(ReaderPagerItem.page))
            items.append(.nextChapter)
        }
        return items
    }

    private var readerBarBackground: some ShapeStyle {
        .ultraThinMaterial
    }

    private var readerCapsuleBackground: some ShapeStyle {
        Color.white.opacity(0.14)
    }

    private var readingModeSymbol: String {
        switch model.state.readerPreferences.mode {
        case .pagerDefault:
            return "rectangle.split.1x2"
        case .pagerLTR:
            return "text.book.closed"
        case .pagerRTL:
            return "text.book.closed.fill"
        case .vertical:
            return "rectangle.stack"
        case .webtoon:
            return "rectangle.portrait.on.rectangle.portrait"
        }
    }

    private var orientationSymbol: String {
        switch model.state.readerPreferences.orientation {
        case .system:
            return "iphone"
        case .portrait:
            return "iphone"
        case .landscape:
            return "iphone.landscape"
        }
    }

    private var chapterLeadingIcon: String {
        isRTLPager ? "chevron.right" : "chevron.left"
    }

    private var chapterTrailingIcon: String {
        isRTLPager ? "chevron.left" : "chevron.right"
    }

    private var isRTLPager: Bool {
        switch model.state.readerPreferences.mode {
        case .pagerDefault, .pagerRTL:
            return true
        case .pagerLTR, .vertical, .webtoon:
            return false
        }
    }

    private func handleTap(atX x: CGFloat, width: CGFloat) {
        let zone = width / 3
        if showingChrome {
            toggleChrome()
            return
        }

        if x < zone {
            if isRTLPager {
                advancePageForward()
            } else {
                advancePageBackward()
            }
        } else if x > zone * 2 {
            if isRTLPager {
                advancePageBackward()
            } else {
                advancePageForward()
            }
        } else {
            toggleChrome()
        }
    }

    private func advancePageForward() {
        if pageIndex + 1 < currentPages.count {
            pageIndex += 1
            return
        }
        if let chapter = nextChapterForCurrentMode() {
            transitionToChapter(chapter, pageIndex: 0)
        }
    }

    private func advancePageBackward() {
        if pageIndex > 0 {
            pageIndex -= 1
            return
        }
        if let chapter = previousChapterForCurrentMode() {
            transitionToChapter(chapter, pageIndex: lastPageIndex(for: chapter))
        }
    }

    private func nextChapterForCurrentMode() -> Chapter? {
        model.nextChapter(after: currentChapter, in: manga)
    }

    private func previousChapterForCurrentMode() -> Chapter? {
        model.previousChapter(before: currentChapter, in: manga)
    }

    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.18)) {
            showingChrome.toggle()
        }
    }

    private func cycleReadingMode() {
        let current = model.state.readerPreferences.mode
        let modes = ReaderMode.allCases
        guard let index = modes.firstIndex(of: current) else { return }
        let next = modes[(index + 1) % modes.count]
        model.setReaderMode(next)
    }

    private func cycleOrientation() {
        let current = model.state.readerPreferences.orientation
        let modes = ReaderOrientation.allCases
        guard let index = modes.firstIndex(of: current) else { return }
        let next = modes[(index + 1) % modes.count]
        model.setReaderOrientation(next)
    }

    private func persistProgress() {
        model.updateProgress(for: manga, chapter: currentChapter, pageIndex: pageIndex)
    }

    private func transitionToChapter(_ chapter: Chapter, pageIndex targetPageIndex: Int) {
        canPersistPageProgress = false
        pendingPageIndexAfterChapterChange = targetPageIndex
        pageLoadState = .idle
        currentChapter = chapter
    }

    private func lastPageIndex(for chapter: Chapter) -> Int {
        if !chapter.pages.isEmpty {
            return max(chapter.pages.count - 1, 0)
        }
        if let cached = model.chapters(for: manga).first(where: { $0.id == chapter.id }) {
            return max(cached.pages.count - 1, 0)
        }
        return 0
    }

    private func startPageLoad(forceRefresh: Bool) {
        if !forceRefresh, !currentPages.isEmpty {
            if pageLoadState != .loaded {
                pageLoadState = .loaded
            }
            finalizeResolvedPages()
            return
        }
        let requestID = UUID()
        activeLoadRequestID = requestID
        let chapterSnapshot = currentChapter
        canPersistPageProgress = false
        pageLoadState = .loading
        Task {
            let pages = forceRefresh
                ? await model.retryPages(for: chapterSnapshot, sourceID: manga.sourceID)
                : await model.refreshPages(for: chapterSnapshot, sourceID: manga.sourceID)
            await MainActor.run {
                applyLoadedPages(pages, requestID: requestID, chapterSnapshot: chapterSnapshot, forceRefresh: forceRefresh)
            }
        }
    }

    private func applyLoadedPages(_ pages: [ReaderPage], requestID: UUID, chapterSnapshot: Chapter, forceRefresh: Bool) {
        guard requestID == activeLoadRequestID else { return }
        guard chapterSnapshot.id == currentChapter.id else { return }

        if !pages.isEmpty {
            currentChapter = Chapter(
                id: currentChapter.id,
                mangaID: currentChapter.mangaID,
                title: currentChapter.title,
                number: currentChapter.number,
                releaseDate: currentChapter.releaseDate,
                isDownloaded: currentChapter.isDownloaded,
                pages: pages
            )
        }

        if forceRefresh {
            retryTick += 1
        }

        pageLoadState = currentPages.isEmpty ? .failed : .loaded
        finalizeResolvedPages()
    }

    private func pagerDisplayIndex(for actualIndex: Int) -> Int {
        let boundedActualIndex = boundedPageIndex(for: actualIndex)
        let baseIndex = isRTLPager ? max(currentPages.count - 1 - boundedActualIndex, 0) : boundedActualIndex
        return baseIndex + 1
    }

    private func actualPageIndex(forDisplayedIndex displayedIndex: Int) -> Int {
        let pageDisplayIndex = min(max(displayedIndex - 1, 0), max(currentPages.count - 1, 0))
        let actualIndex = isRTLPager ? max(currentPages.count - 1 - pageDisplayIndex, 0) : pageDisplayIndex
        return boundedPageIndex(for: actualIndex)
    }

    private func prefetchAroundCurrentPage() {
        let prefetchCount = model.state.advancedPreferences.imagePrefetchCount
        guard prefetchCount > 0 else { return }
        prefetchTask?.cancel()
        let chapterID = currentChapter.id
        let window = currentPages.enumerated().compactMap { index, page -> URL? in
            guard abs(index - pageIndex) <= prefetchCount, let remoteURL = page.remoteURL else { return nil }
            return URL(string: remoteURL)
        }
        guard !window.isEmpty else { return }
        prefetchTask = Task {
            await ReaderImagePipeline.shared.prefetch(window, chapterID: chapterID, limit: prefetchCount)
        }
    }

    private func finalizeResolvedPages() {
        guard !currentPages.isEmpty else {
            canPersistPageProgress = false
            return
        }

        canPersistPageProgress = false
        let targetIndex = pendingPageIndexAfterChapterChange
            ?? (!hasAppliedResumeProgress ? currentChapterResumeProgress?.pageIndex : nil)
            ?? pageIndex
        let boundedIndex = boundedPageIndex(for: targetIndex)
        pageIndex = boundedIndex
        hasAppliedResumeProgress = true
        pendingPageIndexAfterChapterChange = nil
        syncPagerDisplayIndex(animated: false)
        prefetchAroundCurrentPage()
        persistProgress()
        canPersistPageProgress = true
    }

    private func syncPagerDisplayIndex(animated: Bool) {
        guard !isVerticalReader else { return }
        let targetIndex = pagerDisplayIndex(for: pageIndex)
        guard targetIndex != pagerDisplayIndex else { return }
        if animated {
            withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.9)) {
                pagerDisplayIndex = targetIndex
            }
        } else {
            pagerDisplayIndex = targetIndex
        }
    }

    private func handlePagerDisplayIndexChange(_ newIndex: Int) {
        guard pagerItems.indices.contains(newIndex) else { return }
        switch pagerItems[newIndex] {
        case .page:
            let actualIndex = actualPageIndex(forDisplayedIndex: newIndex)
            if actualIndex != pageIndex {
                pageIndex = actualIndex
            }
        case .previousChapter, .nextChapter:
            break
        }
    }

    private func handlePagerBoundaryAdvance(translationWidth: CGFloat) {
        guard pagerItems.indices.contains(pagerDisplayIndex) else { return }
        let movingForward = isRTLPager ? translationWidth > 0 : translationWidth < 0
        switch pagerItems[pagerDisplayIndex] {
        case .nextChapter:
            guard movingForward, let chapter = nextChapterForCurrentMode() else { return }
            transitionToChapter(chapter, pageIndex: 0)
        case .previousChapter:
            guard !movingForward, let chapter = previousChapterForCurrentMode() else { return }
            transitionToChapter(chapter, pageIndex: lastPageIndex(for: chapter))
        case .page:
            break
        }
    }

    private func boundedPageIndex(for index: Int) -> Int {
        min(max(index, 0), max(currentPages.count - 1, 0))
    }

    private func pageAnchorID(for index: Int) -> String {
        "\(retryTick)-\(currentChapter.id)-\(index)"
    }

    private func scrollToCurrentPage(using proxy: ScrollViewProxy, animated: Bool) {
        guard isVerticalReader, pageLoadState == .loaded, !currentPages.isEmpty else { return }
        let action = {
            proxy.scrollTo(pageAnchorID(for: boundedPageIndex(for: pageIndex)), anchor: .top)
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.2), action)
        } else {
            action()
        }
    }

    private func updateVerticalPageIndex(from frames: [Int: CGRect], viewportHeight: CGFloat) {
        guard isVerticalReader, pageLoadState == .loaded, !frames.isEmpty else { return }
        let viewport = CGRect(x: 0, y: 0, width: 1, height: viewportHeight)
        let visibleFrames = frames.filter { _, frame in
            !frame.intersection(viewport).isNull
        }
        guard !visibleFrames.isEmpty else { return }

        let selectedIndex: Int?
        if let coveringTop = visibleFrames
            .filter({ _, frame in frame.minY <= 1 && frame.maxY > 1 })
            .min(by: { lhs, rhs in lhs.key < rhs.key }) {
            selectedIndex = coveringTop.key
        } else {
            selectedIndex = visibleFrames.min(by: { lhs, rhs in
                if lhs.value.minY == rhs.value.minY {
                    return lhs.key < rhs.key
                }
                return lhs.value.minY < rhs.value.minY
            })?.key
        }

        guard let selectedIndex else { return }
        let boundedIndex = boundedPageIndex(for: selectedIndex)
        if boundedIndex != pageIndex {
            pageIndex = boundedIndex
        }
    }
}

private struct ReaderChromeButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
    }
}

private enum ReaderPagerItem: Identifiable {
    case previousChapter
    case page(ReaderPage)
    case nextChapter

    var id: String {
        switch self {
        case .previousChapter:
            return "transition-previous"
        case .page(let page):
            return page.id
        case .nextChapter:
            return "transition-next"
        }
    }
}

private struct ReaderVisiblePageFramesPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct ReaderPagedContainer<Content: View>: View {
    @Binding var currentIndex: Int
    let itemCount: Int
    let canMoveBackward: Bool
    let canMoveForward: Bool
    let onPageChanged: (Int) -> Void
    let onBoundaryAdvance: (CGFloat) -> Void
    @ViewBuilder let content: Content

    @GestureState private var dragTranslation: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .offset(x: -CGFloat(currentIndex) * geometry.size.width + dragTranslation)
                .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.9), value: currentIndex)
                .contentShape(Rectangle())
                .clipped()
                .gesture(
                    DragGesture(minimumDistance: 12, coordinateSpace: .local)
                        .updating($dragTranslation) { value, state, _ in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            state = value.translation.width
                        }
                        .onEnded { value in
                            handleDragEnded(value, width: geometry.size.width)
                        }
                )
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value, width: CGFloat) {
        guard itemCount > 0 else { return }
        guard abs(value.translation.width) > abs(value.translation.height) else { return }

        let threshold = max(width * 0.18, 48)
        let predicted = value.predictedEndTranslation.width
        let shouldMove = abs(value.translation.width) > threshold || abs(predicted) > width * 0.32
        guard shouldMove else { return }

        let movingLeft = value.translation.width < 0
        let nextIndex = min(max(currentIndex + (movingLeft ? 1 : -1), 0), itemCount - 1)

        if nextIndex != currentIndex {
            currentIndex = nextIndex
            onPageChanged(nextIndex)
            return
        }

        if movingLeft, !canMoveForward {
            onBoundaryAdvance(value.translation.width)
        } else if !movingLeft, !canMoveBackward {
            onBoundaryAdvance(value.translation.width)
        }
    }
}

private struct ReaderTransitionPage: View {
    let title: String
    let chapterTitle: String?
    let systemImage: String
    let isEnabled: Bool

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white.opacity(isEnabled ? 0.9 : 0.35))
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.45))
                Text(chapterTitle ?? "No chapter available")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(isEnabled ? 0.72 : 0.3))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ReaderBottomPill: View {
    let systemImage: String
    let title: String
    var isProminent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.headline)
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var backgroundStyle: some ShapeStyle {
        if isProminent {
            return AnyShapeStyle(Color.white.opacity(0.18))
        }
        return AnyShapeStyle(Color.white.opacity(0.08))
    }
}

private struct ReaderPageSurface: View {
    @EnvironmentObject private var model: AppModel
    let page: ReaderPage
    let filter: ReaderColorFilter
    let fillViewport: Bool
    let allowsImagePan: Bool
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black

            content
                .grayscale(filter.enabled ? filter.grayscale : 0)
                .brightness(filter.enabled ? -filter.dimming * 0.4 : 0)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: fillViewport ? .infinity : nil)
    }

    @ViewBuilder
    private var content: some View {
        if page.assetKind == .image, page.assetPath != nil {
            CachedLocalImageView(page: page) { image in
                zoomableImage(image.resizable())
            }
        } else if page.assetKind == .image, let remoteURL = page.remoteURL, let url = URL(string: remoteURL) {
            ReaderRemoteImageView(
                url: url,
                page: page,
                aggressiveRetry: model.state.advancedPreferences.aggressiveImageRetry
            ) { image in
                zoomableImage(image.resizable())
            }
        } else {
            ScrollView {
                Text(page.body)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func zoomableImage(_ image: Image) -> some View {
        let zoomGesture = MagnificationGesture()
            .onChanged { scale = max(1, $0) }
            .onEnded { _ in
                if scale < 1 {
                    scale = 1
                }
                if scale <= 1.01 {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        offset = .zero
                    }
                }
            }

        let base = image
            .interpolation(.high)
            .antialiased(true)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: fillViewport ? .infinity : nil)
            .contentShape(Rectangle())
            .gesture(zoomGesture)

        if allowsImagePan {
            base.simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        guard scale > 1.01 else { return }
                        offset = value.translation
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            if scale <= 1.01 {
                                offset = .zero
                            }
                        }
                    }
            )
        } else {
            base
        }
    }
}

private struct ReaderRemoteImageView<Content: View>: View {
    @EnvironmentObject private var model: AppModel
    let url: URL
    let page: ReaderPage
    let aggressiveRetry: Bool
    @ViewBuilder let content: (Image) -> Content

    @State private var phase: RemoteImagePhase = .loading
    @State private var retryToken = 0

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            case .success(let image):
                content(Image(uiImage: image))
            case .failure(let message):
                VStack(spacing: 14) {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.85))
                        Text("Image Failed")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .allowsHitTesting(false)

                    Button("Retry") {
                        retryToken += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.18))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: retryToken) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        phase = .loading
        do {
            let image = try await ReaderImagePipeline.shared.image(for: url, forceRefresh: retryToken > 0)
            phase = .success(image)
        } catch {
            model.appendDiagnostic(
                kind: .reader,
                title: "Reader Remote Image Failed",
                message: error.localizedDescription,
                metadata: [
                    "pageID": page.id,
                    "url": url.absoluteString
                ]
            )
            if aggressiveRetry, retryToken == 0 {
                do {
                    let image = try await ReaderImagePipeline.shared.image(for: url, forceRefresh: true)
                    phase = .success(image)
                    return
                } catch { }
            }
            phase = .failure("Tap retry to request the page again.")
        }
    }
}

private enum RemoteImagePhase {
    case loading
    case success(UIImage)
    case failure(String)
}

actor ReaderImagePipeline {
    static let shared = ReaderImagePipeline()

    private let cache: AppCacheManaging = AppCacheController.shared
    private var inFlight: [URL: Task<UIImage, Error>] = [:]
    private var prefetchTasksByURL: [URL: Task<Void, Never>] = [:]
    private var activePrefetchChapterID: String?

    func image(for url: URL, forceRefresh: Bool) async throws -> UIImage {
        if !forceRefresh, let task = inFlight[url] {
            return try await task.value
        }

        let task = Task<UIImage, Error> {
            var request = URLRequest(url: url)
            request.cachePolicy = forceRefresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
            request.timeoutInterval = 20
            return try await cache.image(
                for: url,
                key: "reader-image|\(url.absoluteString)",
                policy: forceRefresh ? .reloadIgnoringCache : .returnCacheElseLoad,
                intent: .readerFullQuality
            ) {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                    throw URLError(.badServerResponse)
                }
                return data
            }
        }

        inFlight[url] = task

        do {
            let image = try await task.value
            inFlight[url] = nil
            return image
        } catch {
            inFlight[url] = nil
            throw error
        }
    }

    func prefetch(_ urls: [URL], chapterID: String, limit: Int) async {
        let boundedURLs = Array(urls.prefix(max(limit, 0)))
        let targetSet = Set(boundedURLs)

        if activePrefetchChapterID != chapterID {
            cancelPrefetchTasks()
            activePrefetchChapterID = chapterID
        }

        for (url, task) in prefetchTasksByURL where !targetSet.contains(url) {
            task.cancel()
            prefetchTasksByURL[url] = nil
        }

        for url in boundedURLs {
            if Task.isCancelled { return }
            if inFlight[url] != nil || prefetchTasksByURL[url] != nil { continue }
            let task = Task<Void, Never> {
                defer {
                    Task { await self.finishPrefetch(for: url) }
                }
                guard !Task.isCancelled else { return }
                _ = try? await image(for: url, forceRefresh: false)
            }
            prefetchTasksByURL[url] = task
        }
    }

    func clear() async {
        cancelPrefetchTasks()
        for (_, task) in inFlight {
            task.cancel()
        }
        inFlight.removeAll()
        await cache.clear(.image)
    }

    func cancelPrefetch(for chapterID: String? = nil) {
        guard chapterID == nil || chapterID == activePrefetchChapterID else { return }
        cancelPrefetchTasks()
        activePrefetchChapterID = nil
    }

    private func cancelPrefetchTasks() {
        for task in prefetchTasksByURL.values {
            task.cancel()
        }
        prefetchTasksByURL.removeAll()
    }

    private func finishPrefetch(for url: URL) {
        prefetchTasksByURL[url] = nil
    }
}

private struct CachedLocalImageView<Content: View>: View {
    @EnvironmentObject private var model: AppModel
    let page: ReaderPage
    @ViewBuilder let content: (Image) -> Content

    @State private var phase: LocalImagePhase = .loading

    var body: some View {
        Group {
            switch phase {
            case .loading:
                Rectangle()
                    .fill(.clear)
                    .task(id: page.id) {
                        await loadFromDisk()
                    }
            case .success(let uiImage):
                content(Image(uiImage: uiImage))
            case .failure(let message):
                ReaderInlineFailureView(title: "Downloaded Page Failed", message: message)
            }
        }
    }

    @MainActor
    private func loadFromDisk() async {
        guard let fileURL = model.fileURL(for: page) else {
            phase = .failure("The downloaded file could not be found.")
            model.appendDiagnostic(
                kind: .reader,
                title: "Reader Local Asset Missing",
                message: "A downloaded page file could not be resolved.",
                metadata: [
                    "pageID": page.id,
                    "assetPath": page.assetPath ?? "<nil>",
                    "remoteURL": page.remoteURL ?? "<nil>"
                ]
            )
            return
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            phase = .failure("The downloaded file is missing from storage.")
            model.appendDiagnostic(
                kind: .reader,
                title: "Reader Local Asset Missing",
                message: "A downloaded page path resolved, but the file is absent on disk.",
                metadata: [
                    "pageID": page.id,
                    "assetPath": fileURL.path
                ]
            )
            return
        }

        guard
            let data = try? Data(contentsOf: fileURL),
            let image = UIImage(data: data)
        else {
            phase = .failure("The downloaded file could not be decoded.")
            model.appendDiagnostic(
                kind: .reader,
                title: "Reader Local Decode Failed",
                message: "A downloaded page file exists but could not be decoded into an image.",
                metadata: [
                    "pageID": page.id,
                    "assetPath": fileURL.path
                ]
            )
            return
        }

        phase = .success(image)
    }
}

private enum LocalImagePhase {
    case loading
    case success(UIImage)
    case failure(String)
}

private struct ReaderInlineFailureView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.82))
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum ReaderContentLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed
}

private struct ReaderEmptyState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 34))
                .foregroundStyle(.white.opacity(0.7))
            Text("Chapter could not be displayed")
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.18))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea()
    }
}
