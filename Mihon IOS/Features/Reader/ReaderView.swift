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
    @State private var pageImageSizes: [String: CGSize] = [:]
    @State private var deferredResumePageIndex: Int?
    @State private var surfaceInteractionStates: [String: ReaderInteractionState] = [:]
    @State private var transitionState: ReaderTransitionState?
    @State private var isChapterTransitioning = false
    @State private var pendingVerticalScrollTarget: Int?

    private let verticalScrollCoordinateSpace = "reader.vertical.scroll"
    private static let chapterEndPageTarget = Int.max

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
                                handleTap(at: value.location, in: geometry.size)
                            }
                    )
            }

            if showingChrome {
                readerChrome
                    .transition(.opacity)
            }
        }
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
            guard !logicalPages.isEmpty else { return }
            let boundedPageIndex = boundedPageIndex(for: newValue)
            if boundedPageIndex != newValue {
                pageIndex = boundedPageIndex
                return
            }
            if canPersistPageProgress, let deferredResumePageIndex, deferredResumePageIndex != newValue {
                self.deferredResumePageIndex = nil
            }
            prefetchAroundCurrentPage()
            guard canPersistPageProgress, pageLoadState == .loaded else { return }
            persistProgress()
        }
        .onChange(of: currentChapter.id) { _, _ in
            canPersistPageProgress = false
            pageImageSizes = [:]
            deferredResumePageIndex = nil
            surfaceInteractionStates = [:]
            transitionState = nil
            pendingVerticalScrollTarget = nil
            pageIndex = pendingPageIndexAfterChapterChange ?? 0
            hasAppliedResumeProgress = false
            startPageLoad(forceRefresh: false)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, canPersistPageProgress, !logicalPages.isEmpty { persistProgress() }
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
                        LazyVStack(spacing: isWebtoonMode ? 0 : 12) {
                            if let chapter = previousChapterForCurrentMode() {
                                ReaderTransitionPage(
                                    title: "Previous Chapter",
                                    chapterTitle: chapter.title,
                                    systemImage: chapterLeadingIcon,
                                    isEnabled: true,
                                    progress: transitionProgress(for: .previous),
                                    isLoading: isChapterTransitioning && transitionDirection == .previous,
                                    confirmLabel: "Load Previous",
                                    action: {
                                        confirmChapterTransition(.previous)
                                    }
                                )
                                .frame(minHeight: 220)
                            }

                            ForEach(Array(verticalRenderItems.enumerated()), id: \.element.id) { offset, item in
                                ReaderPageSurface(
                                    item: item,
                                    filter: model.state.readerPreferences.colorFilter,
                                    fillViewport: false,
                                    allowsImagePan: false,
                                    onImageMetadataResolved: { size in
                                        registerImageSize(size, for: item.page.id)
                                    },
                                    onInteractionStateChanged: { _ in
                                    }
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

                            if let chapter = nextChapterForCurrentMode() {
                                ReaderTransitionPage(
                                    title: "Next Chapter",
                                    chapterTitle: chapter.title,
                                    systemImage: chapterTrailingIcon,
                                    isEnabled: true,
                                    progress: transitionProgress(for: .next),
                                    isLoading: isChapterTransitioning && transitionDirection == .next,
                                    confirmLabel: "Load Next",
                                    action: {
                                        confirmChapterTransition(.next)
                                    }
                                )
                                .frame(minHeight: 220)
                            }
                        }
                        .padding(.vertical, isWebtoonMode ? 0 : 12)
                    }
                    .coordinateSpace(name: verticalScrollCoordinateSpace)
                    .ignoresSafeArea()
                    .simultaneousGesture(verticalBoundaryGesture)
                    .onAppear {
                        scrollToCurrentPage(using: scrollProxy, animated: false)
                    }
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
                    .onChange(of: pendingVerticalScrollTarget) { _, target in
                        guard target != nil else { return }
                        scrollToCurrentPage(using: scrollProxy, animated: true)
                        pendingVerticalScrollTarget = nil
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
            allowsInteractivePaging: allowsInteractivePagerDragging,
            onDragChanged: { translation in
                handlePagerDragChanged(translationWidth: translation)
            },
            onDragEnded: { translation, predicted, containerWidth in
                handlePagerDragEnded(
                    translationWidth: translation,
                    predictedTranslationWidth: predicted,
                    containerWidth: containerWidth
                )
            }
        ) {
            HStack(spacing: 0) {
                ForEach(Array(pagerItems.enumerated()), id: \.element.id) { _, item in
                    Group {
                        switch item {
                        case .render(let renderItem):
                            ReaderPageSurface(
                                item: renderItem,
                                filter: model.state.readerPreferences.colorFilter,
                                fillViewport: true,
                                allowsImagePan: true,
                                onImageMetadataResolved: { size in
                                    registerImageSize(size, for: renderItem.page.id)
                                },
                                onInteractionStateChanged: { state in
                                    updateSurfaceInteractionState(state, for: renderItem.id)
                                }
                            )
                        case .previousChapter:
                            ReaderTransitionPage(
                                title: "Previous Chapter",
                                chapterTitle: previousChapterForCurrentMode()?.title,
                                systemImage: chapterLeadingIcon,
                                isEnabled: previousChapterForCurrentMode() != nil,
                                progress: transitionProgress(for: .previous),
                                isLoading: isChapterTransitioning && transitionDirection == .previous,
                                confirmLabel: "Load Previous",
                                action: {
                                    confirmChapterTransition(.previous)
                                }
                            )
                        case .nextChapter:
                            ReaderTransitionPage(
                                title: "Next Chapter",
                                chapterTitle: nextChapterForCurrentMode()?.title,
                                systemImage: chapterTrailingIcon,
                                isEnabled: nextChapterForCurrentMode() != nil,
                                progress: transitionProgress(for: .next),
                                isLoading: isChapterTransitioning && transitionDirection == .next,
                                confirmLabel: "Load Next",
                                action: {
                                    confirmChapterTransition(.next)
                                }
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
        .onChange(of: model.state.readerPreferences.mode) { oldMode, newMode in
            remapPageIndexForModeChange(from: oldMode, to: newMode)
            syncPagerDisplayIndex(animated: false)
        }
    }

    private var verticalBoundaryGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onChanged { value in
                guard isVerticalReader, !isNavigationSuspended else { return }
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                if value.translation.height > 0, pageIndex == 0, previousChapterForCurrentMode() != nil {
                    updateTransitionProgress(for: .previous, translationMagnitude: value.translation.height)
                } else if value.translation.height < 0, pageIndex >= max(logicalPages.count - 1, 0), nextChapterForCurrentMode() != nil {
                    updateTransitionProgress(for: .next, translationMagnitude: -value.translation.height)
                } else if transitionDirection != nil {
                    resetTransitionState()
                }
            }
            .onEnded { value in
                guard isVerticalReader, !isNavigationSuspended else { return }
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                if value.translation.height > 0, pageIndex == 0, previousChapterForCurrentMode() != nil {
                    if transitionProgress(for: .previous) >= 1 {
                        confirmChapterTransition(.previous)
                    } else {
                        resetTransitionState()
                    }
                } else if value.translation.height < 0, pageIndex >= max(logicalPages.count - 1, 0), nextChapterForCurrentMode() != nil {
                    if transitionProgress(for: .next) >= 1 {
                        confirmChapterTransition(.next)
                    } else {
                        resetTransitionState()
                    }
                } else {
                    resetTransitionState()
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
        let total = max(logicalPages.count, 1)
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
                                    if isVerticalReader {
                                        pendingVerticalScrollTarget = newIndex
                                    }
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

    private var isWebtoonMode: Bool {
        model.state.readerPreferences.mode == .webtoon
    }

    private var isNavigationSuspended: Bool {
        isChapterTransitioning || pageLoadState == .loading
    }

    private var transitionDirection: ReaderTransitionDirection? {
        transitionState?.direction
    }

    private var readerRenderData: ReaderRenderData {
        ReaderRenderData.build(
            pages: currentPages,
            mode: model.state.readerPreferences.mode,
            imageSizes: pageImageSizes
        )
    }

    private var logicalPages: [ReaderLogicalPage] {
        readerRenderData.logicalPages
    }

    private var verticalRenderItems: [ReaderRenderItem] {
        readerRenderData.renderItems
    }

    private var pagerRenderItems: [ReaderRenderItem] {
        readerRenderData.renderItems
    }

    private var pagerItems: [ReaderPagerItem] {
        var items: [ReaderPagerItem] = []
        if isRTLPager {
            items.append(.nextChapter)
            items.append(contentsOf: pagerRenderItems.map(ReaderPagerItem.render))
            items.append(.previousChapter)
        } else {
            items.append(.previousChapter)
            items.append(contentsOf: pagerRenderItems.map(ReaderPagerItem.render))
            items.append(.nextChapter)
        }
        return items
    }

    private var currentPagerRenderItem: ReaderRenderItem? {
        guard pagerItems.indices.contains(pagerDisplayIndex) else { return nil }
        guard case .render(let item) = pagerItems[pagerDisplayIndex] else { return nil }
        return item
    }

    private var currentPagerInteractionState: ReaderInteractionState {
        guard let currentPagerRenderItem else { return .default }
        return surfaceInteractionStates[currentPagerRenderItem.id] ?? .default
    }

    private var currentPagerTransitionDirection: ReaderTransitionDirection? {
        guard pagerItems.indices.contains(pagerDisplayIndex) else { return nil }
        switch pagerItems[pagerDisplayIndex] {
        case .previousChapter:
            return .previous
        case .nextChapter:
            return .next
        case .render:
            return nil
        }
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

    private func handleTap(at point: CGPoint, in size: CGSize) {
        guard !isNavigationSuspended else { return }
        if currentPagerTransitionDirection != nil {
            return
        }
        let zone = ReaderTapZone.resolve(point: point, in: size)
        switch zone.intent(isRTLPager: isRTLPager) {
        case .toggleChrome:
            toggleChrome()
        case .forward:
            guard canRouteTapPageTurn else { return }
            advancePageForward()
        case .backward:
            guard canRouteTapPageTurn else { return }
            advancePageBackward()
        case .none:
            break
        }
    }

    private func advancePageForward() {
        if pageIndex + 1 < logicalPages.count {
            let newIndex = pageIndex + 1
            pageIndex = newIndex
            if isVerticalReader {
                pendingVerticalScrollTarget = newIndex
            }
            return
        }
        if isVerticalReader {
            return
        }
        if let index = pagerTransitionIndex(for: .next) {
            pagerDisplayIndex = index
            resetTransitionState()
        }
    }

    private func advancePageBackward() {
        if pageIndex > 0 {
            let newIndex = pageIndex - 1
            pageIndex = newIndex
            if isVerticalReader {
                pendingVerticalScrollTarget = newIndex
            }
            return
        }
        if isVerticalReader {
            return
        }
        if let index = pagerTransitionIndex(for: .previous) {
            pagerDisplayIndex = index
            resetTransitionState()
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
        model.updateProgress(for: manga, chapter: currentChapter, pageIndex: pageIndex, totalPages: logicalPages.count)
    }

    private func transitionToChapter(_ chapter: Chapter, pageIndex targetPageIndex: Int) {
        canPersistPageProgress = false
        pendingPageIndexAfterChapterChange = targetPageIndex
        pageLoadState = .idle
        isChapterTransitioning = true
        transitionState = nil
        currentChapter = chapter
    }

    private func lastPageIndex(for chapter: Chapter) -> Int {
        if chapter.id == currentChapter.id {
            return max(logicalPages.count - 1, 0)
        }
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
        if pageLoadState != .loading {
            isChapterTransitioning = false
        }
        finalizeResolvedPages()
    }

    private func pagerDisplayIndex(for actualIndex: Int) -> Int {
        let boundedActualIndex = boundedPageIndex(for: actualIndex)
        return pagerItems.firstIndex { item in
            guard case .render(let renderItem) = item else { return false }
            return renderItem.logicalPageIndex == boundedActualIndex
        } ?? 1
    }

    private func prefetchAroundCurrentPage() {
        let prefetchCount = model.state.advancedPreferences.imagePrefetchCount
        guard prefetchCount > 0 else { return }
        prefetchTask?.cancel()
        let chapterID = currentChapter.id
        let windowPages = logicalPages.enumerated().compactMap { index, logicalPage -> ReaderPage? in
            guard abs(index - pageIndex) <= prefetchCount else { return nil }
            return logicalPage.sourcePage
        }
        let window = Array(Set(windowPages.compactMap { page -> URL? in
            guard let remoteURL = page.remoteURL else { return nil }
            return URL(string: remoteURL)
        }))
        guard !window.isEmpty else { return }
        prefetchTask = Task {
            await ReaderImagePipeline.shared.prefetch(window, chapterID: chapterID, limit: prefetchCount)
        }
    }

    private func finalizeResolvedPages() {
        guard !logicalPages.isEmpty else {
            canPersistPageProgress = false
            return
        }

        canPersistPageProgress = false
        let targetIndex = pendingPageIndexAfterChapterChange
            ?? (!hasAppliedResumeProgress ? currentChapterResumeProgress?.pageIndex : nil)
            ?? pageIndex
        let boundedIndex = targetIndex == Self.chapterEndPageTarget
            ? max(logicalPages.count - 1, 0)
            : boundedPageIndex(for: targetIndex)
        pageIndex = boundedIndex
        deferredResumePageIndex = targetIndex == Self.chapterEndPageTarget || targetIndex > boundedIndex ? targetIndex : nil
        hasAppliedResumeProgress = true
        pendingPageIndexAfterChapterChange = nil
        resetTransitionState()
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
        case .render(let renderItem):
            if renderItem.logicalPageIndex != pageIndex {
                pageIndex = renderItem.logicalPageIndex
            }
        case .previousChapter, .nextChapter:
            break
        }
    }

    private var canRouteTapPageTurn: Bool {
        if currentPagerTransitionDirection != nil {
            return false
        }
        return !currentPagerInteractionState.consumesTapNavigation
    }

    private var allowsInteractivePagerDragging: Bool {
        if currentPagerTransitionDirection != nil {
            return true
        }
        if currentPagerInteractionState.scale <= 1.01 {
            return true
        }
        return !currentPagerInteractionState.readyDirections.isEmpty
    }

    private func boundedPageIndex(for index: Int) -> Int {
        min(max(index, 0), max(logicalPages.count - 1, 0))
    }

    private func pageAnchorID(for index: Int) -> String {
        "\(retryTick)-\(currentChapter.id)-\(index)"
    }

    private func scrollToCurrentPage(using proxy: ScrollViewProxy, animated: Bool) {
        guard isVerticalReader, pageLoadState == .loaded, !verticalRenderItems.isEmpty else { return }
        guard let firstRenderIndex = verticalRenderItems.firstIndex(where: { $0.logicalPageIndex == boundedPageIndex(for: pageIndex) }) else {
            return
        }
        let action = {
            proxy.scrollTo(pageAnchorID(for: firstRenderIndex), anchor: .top)
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
        guard verticalRenderItems.indices.contains(selectedIndex) else { return }
        let logicalIndex = boundedPageIndex(for: verticalRenderItems[selectedIndex].logicalPageIndex)
        if logicalIndex != pageIndex {
            pageIndex = logicalIndex
        }
    }

    private func registerImageSize(_ size: CGSize, for pageID: String) {
        guard size.width > 0, size.height > 0 else { return }
        let rounded = CGSize(width: size.width.rounded(.toNearestOrAwayFromZero), height: size.height.rounded(.toNearestOrAwayFromZero))
        if let existing = pageImageSizes[pageID], existing == rounded {
            return
        }

        let oldData = ReaderRenderData.build(
            pages: currentPages,
            mode: model.state.readerPreferences.mode,
            imageSizes: pageImageSizes
        )
        let anchor = oldData.anchor(for: pageIndex)

        var updatedSizes = pageImageSizes
        updatedSizes[pageID] = rounded
        let newData = ReaderRenderData.build(
            pages: currentPages,
            mode: model.state.readerPreferences.mode,
            imageSizes: updatedSizes
        )

        pageImageSizes = updatedSizes
        if deferredResumePageIndex == Self.chapterEndPageTarget {
            pageIndex = max(newData.logicalPages.count - 1, 0)
            self.deferredResumePageIndex = Self.chapterEndPageTarget
        } else if let deferredResumePageIndex, deferredResumePageIndex < newData.logicalPages.count {
            pageIndex = deferredResumePageIndex
            self.deferredResumePageIndex = nil
        } else if let anchor, let mappedIndex = newData.index(for: anchor) {
            pageIndex = mappedIndex
        } else {
            pageIndex = min(pageIndex, max(newData.logicalPages.count - 1, 0))
        }
        syncPagerDisplayIndex(animated: false)
    }

    private func remapPageIndexForModeChange(from oldMode: ReaderMode, to newMode: ReaderMode) {
        guard oldMode != newMode else { return }
        let oldData = ReaderRenderData.build(
            pages: currentPages,
            mode: oldMode,
            imageSizes: pageImageSizes
        )
        let newData = ReaderRenderData.build(
            pages: currentPages,
            mode: newMode,
            imageSizes: pageImageSizes
        )
        guard let anchor = oldData.anchor(for: pageIndex) else {
            pageIndex = min(pageIndex, max(newData.logicalPages.count - 1, 0))
            return
        }
        if let remappedIndex = newData.index(for: anchor) {
            pageIndex = remappedIndex
        } else {
            pageIndex = min(pageIndex, max(newData.logicalPages.count - 1, 0))
        }
    }

    private func updateSurfaceInteractionState(_ state: ReaderInteractionState, for itemID: String) {
        if surfaceInteractionStates[itemID] == state {
            return
        }
        surfaceInteractionStates[itemID] = state
    }

    private func pagerTransitionIndex(for direction: ReaderTransitionDirection) -> Int? {
        pagerItems.firstIndex { item in
            switch (direction, item) {
            case (.previous, .previousChapter), (.next, .nextChapter):
                return true
            default:
                return false
            }
        }
    }

    private func updateTransitionProgress(for direction: ReaderTransitionDirection, translationMagnitude: CGFloat) {
        let progress = min(max(translationMagnitude / ReaderTransitionState.activationDistance, 0), 1)
        transitionState = ReaderTransitionState(direction: direction, progress: progress, isLoading: false)
    }

    private func transitionProgress(for direction: ReaderTransitionDirection) -> CGFloat {
        guard transitionState?.direction == direction else { return 0 }
        return transitionState?.progress ?? 0
    }

    private func resetTransitionState() {
        if !isChapterTransitioning {
            transitionState = nil
        }
    }

    private func confirmChapterTransition(_ direction: ReaderTransitionDirection) {
        guard !isNavigationSuspended else { return }
        let targetChapter: Chapter?
        let targetPageIndex: Int

        switch direction {
        case .previous:
            targetChapter = previousChapterForCurrentMode()
            targetPageIndex = Self.chapterEndPageTarget
        case .next:
            targetChapter = nextChapterForCurrentMode()
            targetPageIndex = 0
        }

        guard let targetChapter else { return }
        transitionState = ReaderTransitionState(direction: direction, progress: 1, isLoading: true)
        transitionToChapter(targetChapter, pageIndex: targetPageIndex)
    }

    private func isForwardPagerTranslation(_ translationWidth: CGFloat) -> Bool {
        isRTLPager ? translationWidth > 0 : translationWidth < 0
    }

    private func stepPager(movingLeft: Bool) {
        let nextIndex = min(max(pagerDisplayIndex + (movingLeft ? 1 : -1), 0), max(pagerItems.count - 1, 0))
        guard nextIndex != pagerDisplayIndex else { return }
        pagerDisplayIndex = nextIndex
        handlePagerDisplayIndexChange(nextIndex)
        resetTransitionState()
    }

    private func handlePagerDragChanged(translationWidth: CGFloat) {
        guard !isNavigationSuspended else { return }
        guard let direction = currentPagerTransitionDirection else {
            if transitionDirection != nil {
                resetTransitionState()
            }
            return
        }

        let translationMagnitude: CGFloat
        switch direction {
        case .next:
            translationMagnitude = isForwardPagerTranslation(translationWidth) ? abs(translationWidth) : 0
        case .previous:
            translationMagnitude = isForwardPagerTranslation(translationWidth) ? 0 : abs(translationWidth)
        }

        if translationMagnitude > 0 {
            updateTransitionProgress(for: direction, translationMagnitude: translationMagnitude)
        } else if transitionDirection != nil {
            resetTransitionState()
        }
    }

    private func handlePagerDragEnded(
        translationWidth: CGFloat,
        predictedTranslationWidth: CGFloat,
        containerWidth: CGFloat
    ) {
        guard !isNavigationSuspended else { return }
        let threshold = max(containerWidth * 0.18, 48)
        let shouldMove = abs(translationWidth) > threshold || abs(predictedTranslationWidth) > containerWidth * 0.32
        guard shouldMove else {
            resetTransitionState()
            return
        }

        let movingLeft = translationWidth < 0

        if let transitionDirection = currentPagerTransitionDirection {
            if transitionProgress(for: transitionDirection) >= 1 {
                confirmChapterTransition(transitionDirection)
                return
            }
            stepPager(movingLeft: movingLeft)
            return
        }

        if currentPagerInteractionState.scale > 1.01 {
            let dragDirection: ReaderPanEdgeState = movingLeft ? .leftDrag : .rightDrag
            guard currentPagerInteractionState.readyDirections.contains(dragDirection) else { return }
        }

        stepPager(movingLeft: movingLeft)
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

private struct ReaderVisiblePageFramesPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct ReaderRenderData {
    let logicalPages: [ReaderLogicalPage]
    let renderItems: [ReaderRenderItem]

    func anchor(for logicalIndex: Int) -> ReaderLogicalAnchor? {
        guard logicalPages.indices.contains(logicalIndex) else { return nil }
        return logicalPages[logicalIndex].anchor
    }

    func index(for anchor: ReaderLogicalAnchor) -> Int? {
        if let exactIndex = logicalPages.firstIndex(where: { $0.anchor == anchor }) {
            return exactIndex
        }
        return logicalPages.firstIndex(where: { $0.anchor.sourcePageID == anchor.sourcePageID })
    }

    static func build(pages: [ReaderPage], mode: ReaderMode, imageSizes: [String: CGSize]) -> ReaderRenderData {
        switch mode {
        case .pagerDefault, .pagerLTR, .pagerRTL:
            return buildPagedData(pages: pages, mode: mode, imageSizes: imageSizes)
        case .vertical:
            let logicalPages = pages.enumerated().map { index, page in
                ReaderLogicalPage(
                    id: "\(page.id)|full",
                    sourcePage: page,
                    sourcePageIndex: index,
                    kind: .full
                )
            }
            let renderItems = logicalPages.enumerated().map { index, logicalPage in
                ReaderRenderItem(
                    id: logicalPage.id,
                    logicalPageID: logicalPage.id,
                    logicalPageIndex: index,
                    sourcePageIndex: logicalPage.sourcePageIndex,
                    page: logicalPage.sourcePage,
                    fragment: .full
                )
            }
            return ReaderRenderData(logicalPages: logicalPages, renderItems: renderItems)
        case .webtoon:
            return buildWebtoonData(pages: pages, imageSizes: imageSizes)
        }
    }

    private static func buildPagedData(pages: [ReaderPage], mode: ReaderMode, imageSizes: [String: CGSize]) -> ReaderRenderData {
        let logicalPages = pages.enumerated().flatMap { index, page -> [ReaderLogicalPage] in
            guard let size = imageSizes[page.id], size.shouldSplitForSpread else {
                return [
                    ReaderLogicalPage(
                        id: "\(page.id)|full",
                        sourcePage: page,
                        sourcePageIndex: index,
                        kind: .full
                    )
                ]
            }
            return [
                ReaderLogicalPage(
                    id: "\(page.id)|spread-left",
                    sourcePage: page,
                    sourcePageIndex: index,
                    kind: .spreadHalf(.left)
                ),
                ReaderLogicalPage(
                    id: "\(page.id)|spread-right",
                    sourcePage: page,
                    sourcePageIndex: index,
                    kind: .spreadHalf(.right)
                )
            ]
        }

        let baseRenderItems = logicalPages.enumerated().map { index, logicalPage in
            ReaderRenderItem(
                id: logicalPage.id,
                logicalPageID: logicalPage.id,
                logicalPageIndex: index,
                sourcePageIndex: logicalPage.sourcePageIndex,
                page: logicalPage.sourcePage,
                fragment: logicalPage.renderFragment
            )
        }
        let isRTLPager = mode == .pagerDefault || mode == .pagerRTL
        let renderItems = isRTLPager ? Array(baseRenderItems.reversed()) : baseRenderItems
        return ReaderRenderData(logicalPages: logicalPages, renderItems: renderItems)
    }

    private static func buildWebtoonData(pages: [ReaderPage], imageSizes: [String: CGSize]) -> ReaderRenderData {
        let logicalPages = pages.enumerated().map { index, page in
            ReaderLogicalPage(
                id: "\(page.id)|full",
                sourcePage: page,
                sourcePageIndex: index,
                kind: .full
            )
        }

        let renderItems = logicalPages.enumerated().flatMap { logicalIndex, logicalPage -> [ReaderRenderItem] in
            let slices = imageSizes[logicalPage.sourcePage.id]?.webtoonSliceUnitRects ?? [CGRect(x: 0, y: 0, width: 1, height: 1)]
            return slices.enumerated().map { sliceIndex, rect in
                ReaderRenderItem(
                    id: "\(logicalPage.id)|slice-\(sliceIndex)",
                    logicalPageID: logicalPage.id,
                    logicalPageIndex: logicalIndex,
                    sourcePageIndex: logicalPage.sourcePageIndex,
                    page: logicalPage.sourcePage,
                    fragment: slices.count == 1 ? .full : .webtoonSlice(index: sliceIndex, total: slices.count, unitRect: rect)
                )
            }
        }

        return ReaderRenderData(logicalPages: logicalPages, renderItems: renderItems)
    }
}

private struct ReaderLogicalPage: Identifiable {
    let id: String
    let sourcePage: ReaderPage
    let sourcePageIndex: Int
    let kind: ReaderLogicalPageKind

    var anchor: ReaderLogicalAnchor {
        ReaderLogicalAnchor(sourcePageID: sourcePage.id, kind: kind.anchorKey)
    }

    var renderFragment: ReaderRenderFragment {
        switch kind {
        case .full:
            return .full
        case .spreadHalf(let side):
            return .spreadHalf(side)
        }
    }
}

private enum ReaderLogicalPageKind {
    case full
    case spreadHalf(ReaderSpreadHalf)

    var anchorKey: String {
        switch self {
        case .full:
            return "full"
        case .spreadHalf(let side):
            return "spread-\(side.rawValue)"
        }
    }
}

private struct ReaderLogicalAnchor: Equatable {
    let sourcePageID: String
    let kind: String
}

private struct ReaderRenderItem: Identifiable {
    let id: String
    let logicalPageID: String
    let logicalPageIndex: Int
    let sourcePageIndex: Int
    let page: ReaderPage
    let fragment: ReaderRenderFragment
}

private enum ReaderRenderFragment {
    case full
    case spreadHalf(ReaderSpreadHalf)
    case webtoonSlice(index: Int, total: Int, unitRect: CGRect)
}

private enum ReaderSpreadHalf: String {
    case left
    case right

    var unitRect: CGRect {
        switch self {
        case .left:
            return CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .right:
            return CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        }
    }
}

private struct ReaderPagedContainer<Content: View>: View {
    @Binding var currentIndex: Int
    let itemCount: Int
    let allowsInteractivePaging: Bool
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat, CGFloat, CGFloat) -> Void
    @ViewBuilder let content: Content

    @GestureState private var dragTranslation: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .offset(x: -CGFloat(currentIndex) * geometry.size.width + (allowsInteractivePaging ? dragTranslation : 0))
                .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.9), value: currentIndex)
                .contentShape(Rectangle())
                .clipped()
                .gesture(
                    DragGesture(minimumDistance: 12, coordinateSpace: .local)
                        .updating($dragTranslation) { value, state, _ in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            state = allowsInteractivePaging ? value.translation.width : 0
                        }
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            onDragChanged(value.translation.width)
                        }
                        .onEnded { value in
                            onDragChanged(0)
                            onDragEnded(value.translation.width, value.predictedEndTranslation.width, geometry.size.width)
                        }
                )
        }
    }
}

private struct ReaderTransitionPage: View {
    let title: String
    let chapterTitle: String?
    let systemImage: String
    let isEnabled: Bool
    let progress: CGFloat
    let isLoading: Bool
    let confirmLabel: String
    let action: () -> Void

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 18) {
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

                ProgressView(value: progress, total: 1)
                    .tint(.white)
                    .opacity(isEnabled ? 1 : 0.25)
                    .frame(maxWidth: 220)

                Button(isLoading ? "Loading…" : confirmLabel, action: action)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isEnabled || isLoading)
                    .tint(.white.opacity(isEnabled ? 0.18 : 0.08))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
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
    let item: ReaderRenderItem
    let filter: ReaderColorFilter
    let fillViewport: Bool
    let allowsImagePan: Bool
    let onImageMetadataResolved: (CGSize) -> Void
    let onInteractionStateChanged: (ReaderInteractionState) -> Void
    @State private var resolvedSourcePixelSize: CGSize = .zero
    @State private var loadFailureMessage: String?
    @State private var retryToken = 0

    var body: some View {
        ZStack {
            Color.black

            content
        }
        .frame(maxWidth: .infinity, maxHeight: fillViewport ? .infinity : nil)
        .onAppear {
            onInteractionStateChanged(.default)
        }
        .onDisappear {
            onInteractionStateChanged(.default)
        }
    }

    @ViewBuilder
    private var content: some View {
        if item.page.assetKind == .image {
            imageContent
        } else {
            ScrollView {
                Text(item.page.body)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .grayscale(filter.enabled ? filter.grayscale : 0)
            .brightness(filter.enabled ? -filter.dimming * 0.4 : 0)
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        if let imageSource {
            ZStack {
                ReaderTiledPageSurface(
                    source: imageSource,
                    variantKey: item.id,
                    normalizedCropRect: normalizedCropRect,
                    colorTransform: ReaderColorTransform(filter: filter),
                    allowsZoom: allowsImagePan,
                    retryToken: retryToken,
                    onSourceSizeResolved: { size in
                        resolvedSourcePixelSize = size
                        loadFailureMessage = nil
                        onImageMetadataResolved(size)
                    },
                    onViewportStateChanged: { viewportState in
                        var readyDirections: Set<ReaderPanEdgeState> = []
                        if viewportState.isLeftEdgeReadyForPageTurn {
                            readyDirections.insert(.rightDrag)
                        }
                        if viewportState.isRightEdgeReadyForPageTurn {
                            readyDirections.insert(.leftDrag)
                        }
                        onInteractionStateChanged(
                            ReaderInteractionState(
                                scale: viewportState.scale,
                                offset: CGSize(width: viewportState.contentOffset.x, height: viewportState.contentOffset.y),
                                edgeDirection: nil,
                                readyDirections: readyDirections
                            )
                        )
                    },
                    onFailureChanged: { message in
                        loadFailureMessage = message
                        if message != nil {
                            onInteractionStateChanged(.default)
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: fillViewport ? .infinity : nil)
                .aspectRatio(fillViewport ? nil : (resolvedDisplayAspectRatio ?? 0.72), contentMode: .fit)

                if let failureMessage = loadFailureMessage {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.82))
                        Text("Image Failed")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(failureMessage)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        Button("Retry") {
                            retryToken += 1
                            loadFailureMessage = nil
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.18))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 24)
                }
            }
        } else {
            ReaderInlineFailureView(
                title: "Image Failed",
                message: "The page image source could not be resolved."
            )
        }
    }

    private var imageSource: ReaderImageAssetSource? {
        let localFileURL = model.fileURL(for: item.page)
        let remoteURL = item.page.remoteURL.flatMap(URL.init(string:))
        guard localFileURL != nil || remoteURL != nil else { return nil }
        let sourceIdentity = localFileURL?.path ?? remoteURL?.absoluteString ?? item.page.id
        return ReaderImageAssetSource(
            cacheKey: "\(item.page.id)|\(sourceIdentity)",
            remoteURL: remoteURL,
            localFileURL: localFileURL
        )
    }

    private var normalizedCropRect: CGRect {
        switch item.fragment {
        case .full:
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        case .spreadHalf(let side):
            return side.unitRect
        case .webtoonSlice(_, _, let unitRect):
            return unitRect
        }
    }

    private var resolvedDisplayAspectRatio: CGFloat? {
        guard resolvedSourcePixelSize.width > 0, resolvedSourcePixelSize.height > 0 else { return nil }
        let displayWidth = resolvedSourcePixelSize.width * normalizedCropRect.width
        let displayHeight = resolvedSourcePixelSize.height * normalizedCropRect.height
        guard displayWidth > 0, displayHeight > 0 else { return nil }
        return displayWidth / displayHeight
    }
}

private struct ReaderRemoteImageView<Content: View>: View {
    @EnvironmentObject private var model: AppModel
    let url: URL
    let page: ReaderPage
    let aggressiveRetry: Bool
    let onImageMetadataResolved: (CGSize) -> Void
    @ViewBuilder let content: (UIImage) -> Content

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
                content(image)
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
            onImageMetadataResolved(image.size)
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
                    onImageMetadataResolved(image.size)
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
    private let ciContext = CIContext(options: nil)

    func previewImage(
        for source: ReaderImageAssetSource,
        variantKey _: String,
        normalizedCropRect: CGRect,
        maxPixelSize: CGFloat,
        colorTransform: ReaderColorTransform,
        forceRefresh: Bool
    ) async throws -> ReaderPreviewImageResult {
        let dimensions = try await cache.readerImageDimensions(
            for: source.cacheKey,
            policy: forceRefresh ? .reloadIgnoringCache : .returnCacheElseLoad
        ) {
            try await self.loadData(for: source, forceRefresh: forceRefresh)
        }
        let previewImage = try await cache.readerPreviewImage(
            for: source.cacheKey,
            policy: forceRefresh ? .reloadIgnoringCache : .returnCacheElseLoad,
            normalizedCropRect: normalizedCropRect,
            maxPixelSize: maxPixelSize
        ) {
            try await self.loadData(for: source, forceRefresh: forceRefresh)
        }
        let transformed = applyColorTransform(colorTransform, to: previewImage) ?? previewImage
        return ReaderPreviewImageResult(image: transformed, sourcePixelSize: dimensions)
    }

    func tileImage(
        for request: ReaderTileRequest,
        variantKey _: String,
        forceRefresh: Bool
    ) async throws -> UIImage {
        let tileImage = try await cache.readerTileImage(
            for: request.source.cacheKey,
            policy: forceRefresh ? .reloadIgnoringCache : .returnCacheElseLoad,
            normalizedCropRect: request.normalizedCropRect,
            targetPixelSize: request.targetPixelSize
        ) {
            try await self.loadData(for: request.source, forceRefresh: forceRefresh)
        }
        return applyColorTransform(request.colorTransform, to: tileImage) ?? tileImage
    }

    private func loadData(for source: ReaderImageAssetSource, forceRefresh: Bool) async throws -> Data {
        if let localFileURL = source.localFileURL {
            return try await Task.detached(priority: .utility) {
                try Data(contentsOf: localFileURL, options: [.mappedIfSafe])
            }.value
        }

        guard let remoteURL = source.remoteURL else {
            throw URLError(.fileDoesNotExist)
        }

        var request = URLRequest(url: remoteURL)
        request.cachePolicy = forceRefresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func applyColorTransform(_ transform: ReaderColorTransform, to image: UIImage) -> UIImage? {
        guard transform.enabled, let cgImage = image.cgImage else { return image }
        let input = CIImage(cgImage: cgImage)

        let controls = CIFilter(name: "CIColorControls")
        controls?.setValue(input, forKey: kCIInputImageKey)
        controls?.setValue(1 - transform.grayscale, forKey: kCIInputSaturationKey)
        controls?.setValue(-transform.dimming * 0.4, forKey: kCIInputBrightnessKey)

        guard
            let output = controls?.outputImage,
            let rendered = ciContext.createCGImage(output, from: output.extent)
        else {
            return image
        }
        return UIImage(cgImage: rendered)
    }

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
    let onImageMetadataResolved: (CGSize) -> Void
    @ViewBuilder let content: (UIImage) -> Content

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
                content(uiImage)
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

        onImageMetadataResolved(image.size)
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

private enum ReaderTapZone {
    case topLeading
    case topCenter
    case topTrailing
    case middleLeading
    case center
    case middleTrailing
    case bottomLeading
    case bottomCenter
    case bottomTrailing

    static func resolve(point: CGPoint, in size: CGSize) -> ReaderTapZone {
        let column = min(max(Int((point.x / max(size.width, 1)) * 3), 0), 2)
        let row = min(max(Int((point.y / max(size.height, 1)) * 3), 0), 2)
        switch (row, column) {
        case (0, 0): return .topLeading
        case (0, 1): return .topCenter
        case (0, 2): return .topTrailing
        case (1, 0): return .middleLeading
        case (1, 1): return .center
        case (1, 2): return .middleTrailing
        case (2, 0): return .bottomLeading
        case (2, 1): return .bottomCenter
        default: return .bottomTrailing
        }
    }

    func intent(isRTLPager: Bool) -> ReaderTapIntent {
        switch self {
        case .center:
            return .toggleChrome
        case .topCenter, .bottomCenter:
            return .none
        case .topLeading, .middleLeading, .bottomLeading:
            return isRTLPager ? .forward : .backward
        case .topTrailing, .middleTrailing, .bottomTrailing:
            return isRTLPager ? .backward : .forward
        }
    }
}

private enum ReaderTapIntent {
    case forward
    case backward
    case toggleChrome
    case none
}

private enum ReaderTransitionDirection {
    case previous
    case next
}

private struct ReaderTransitionState: Equatable {
    static let activationDistance: CGFloat = 120

    let direction: ReaderTransitionDirection
    let progress: CGFloat
    let isLoading: Bool
}

private enum ReaderPanEdgeState: Hashable {
    case leftDrag
    case rightDrag
}

private struct ReaderInteractionState: Equatable {
    static let resistanceThreshold: CGFloat = 72
    static let `default` = ReaderInteractionState(scale: 1, offset: .zero, edgeDirection: nil, readyDirections: [])

    let scale: CGFloat
    let offset: CGSize
    let edgeDirection: ReaderPanEdgeState?
    let readyDirections: Set<ReaderPanEdgeState>

    var consumesTapNavigation: Bool {
        scale > 1.01
    }
}

private struct ReaderPanResolution {
    let clampedOffset: CGSize
    let edgeDirection: ReaderPanEdgeState?
    let overscrollDistance: CGFloat
}

private extension CGSize {
    static let readerSpreadSplitThreshold: CGFloat = 1.32
    static let readerWebtoonSliceHeight: CGFloat = 4_096

    var shouldSplitForSpread: Bool {
        width > 0 && height > 0 && (width / height) >= Self.readerSpreadSplitThreshold
    }

    var webtoonSliceUnitRects: [CGRect] {
        guard width > 0, height > 0, height > Self.readerWebtoonSliceHeight else {
            return [CGRect(x: 0, y: 0, width: 1, height: 1)]
        }

        let sliceCount = Int(ceil(height / Self.readerWebtoonSliceHeight))
        guard sliceCount > 1 else {
            return [CGRect(x: 0, y: 0, width: 1, height: 1)]
        }

        let normalizedSliceHeight = 1 / CGFloat(sliceCount)
        return (0..<sliceCount).map { index in
            let originY = CGFloat(index) * normalizedSliceHeight
            let height = index == sliceCount - 1 ? 1 - originY : normalizedSliceHeight
            return CGRect(x: 0, y: originY, width: 1, height: height)
        }
    }

    func aspectFit(in boundingSize: CGSize) -> CGSize {
        guard width > 0, height > 0, boundingSize.width > 0, boundingSize.height > 0 else {
            return .zero
        }
        let scale = min(boundingSize.width / width, boundingSize.height / height)
        return CGSize(width: width * scale, height: height * scale)
    }
}

private extension UIImage {
    func cropped(unitRect: CGRect) -> UIImage? {
        guard let cgImage else { return nil }
        let pixelRect = CGRect(
            x: unitRect.origin.x * CGFloat(cgImage.width),
            y: unitRect.origin.y * CGFloat(cgImage.height),
            width: unitRect.size.width * CGFloat(cgImage.width),
            height: unitRect.size.height * CGFloat(cgImage.height)
        ).integral

        guard pixelRect.width > 0, pixelRect.height > 0 else { return nil }
        guard let cropped = cgImage.cropping(to: pixelRect) else { return nil }
        return UIImage(cgImage: cropped, scale: scale, orientation: imageOrientation)
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
