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
    @State private var sliderPageIndex: Double
    @State private var showingSettings = false
    @State private var showingActions = false
    @State private var showingChrome = false
    @State private var pageLoadState: ReaderContentLoadState = .idle
    @State private var retryTick = 0
    @State private var pendingPageIndexAfterChapterChange: Int?
    @State private var activeLoadRequestID = UUID()
    @State private var prefetchTask: Task<Void, Never>?

    init(manga: Manga, initialChapter: Chapter) {
        self.manga = manga
        self.initialChapter = initialChapter
        _currentChapter = State(initialValue: initialChapter)
        _pageIndex = State(initialValue: 0)
        _sliderPageIndex = State(initialValue: 1)
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
            if let progress = model.progress(for: manga), progress.chapterID == currentChapter.id {
                pageIndex = min(progress.pageIndex, max(currentPages.count - 1, 0))
                sliderPageIndex = Double(pageIndex + 1)
            }
            persistProgress()
            startPageLoad(forceRefresh: false)
        }
        .onChange(of: pageIndex) { _, newValue in
            pageIndex = min(max(newValue, 0), max(currentPages.count - 1, 0))
            sliderPageIndex = Double(pageIndex + 1)
            persistProgress()
            prefetchAroundCurrentPage()
        }
        .onChange(of: currentChapter.id) { _, _ in
            pageIndex = pendingPageIndexAfterChapterChange ?? 0
            sliderPageIndex = Double(pageIndex + 1)
            persistProgress()
            startPageLoad(forceRefresh: false)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { persistProgress() }
        }
        .onDisappear {
            activeLoadRequestID = UUID()
            prefetchTask?.cancel()
            prefetchTask = nil
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
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: model.state.readerPreferences.mode == .webtoon ? 0 : 12) {
                    ForEach(currentPages) { page in
                        ReaderPageSurface(
                            page: page,
                            filter: model.state.readerPreferences.colorFilter,
                            fillViewport: false,
                            allowsImagePan: false
                        )
                            .id("\(retryTick)-\(page.index)")
                            .onAppear {
                                pageIndex = page.index
                            }
                    }
                }
                .padding(.vertical, model.state.readerPreferences.mode == .webtoon ? 0 : 12)
            }
            .ignoresSafeArea()
            .simultaneousGesture(verticalBoundaryGesture)
        } else {
            TabView(selection: displayedPageSelection) {
                ForEach(Array(pagerItems.enumerated()), id: \.element.id) { displayIndex, item in
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
                    .tag(displayIndex)
                    .ignoresSafeArea()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
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
                            get: { sliderPageIndex },
                            set: { sliderPageIndex = $0 }
                        ),
                        in: 1...Double(total),
                        step: 1
                    )
                    .tint(.white)
                    .onChange(of: sliderPageIndex) { _, value in
                        let newIndex = max(0, min(total - 1, Int(value.rounded()) - 1))
                        if newIndex != pageIndex {
                            pageIndex = newIndex
                        }
                    }
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

    private var displayedPageSelection: Binding<Int> {
        Binding(
            get: { pagerDisplayIndex(for: pageIndex) },
            set: { newValue in
                let bounded = max(0, min(max(pagerItems.count - 1, 0), newValue))
                switch pagerItems[bounded] {
                case .page:
                    pageIndex = actualPageIndex(forDisplayedIndex: bounded)
                case .previousChapter:
                    if let chapter = previousChapterForCurrentMode() {
                        transitionToChapter(chapter, pageIndex: lastPageIndex(for: chapter))
                    }
                case .nextChapter:
                    if let chapter = nextChapterForCurrentMode() {
                        transitionToChapter(chapter, pageIndex: 0)
                    }
                }
            }
        )
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
            pageLoadState = .loaded
            prefetchAroundCurrentPage()
            return
        }
        let requestID = UUID()
        activeLoadRequestID = requestID
        let chapterSnapshot = currentChapter
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

        let targetIndex = pendingPageIndexAfterChapterChange ?? pageIndex
        let boundedPageIndex = min(max(targetIndex, 0), max(currentPages.count - 1, 0))
        pageIndex = boundedPageIndex
        sliderPageIndex = Double(boundedPageIndex + 1)
        pendingPageIndexAfterChapterChange = nil
        pageLoadState = currentPages.isEmpty ? .failed : .loaded
        prefetchAroundCurrentPage()
    }

    private func pagerDisplayIndex(for actualIndex: Int) -> Int {
        let baseIndex = isRTLPager ? max(currentPages.count - 1 - actualIndex, 0) : actualIndex
        return baseIndex + 1
    }

    private func actualPageIndex(forDisplayedIndex displayedIndex: Int) -> Int {
        let pageDisplayIndex = max(displayedIndex - 1, 0)
        return isRTLPager ? max(currentPages.count - 1 - pageDisplayIndex, 0) : pageDisplayIndex
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
            await ReaderImagePipeline.shared.prefetch(window, chapterID: chapterID)
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
        if page.assetKind == .image, let url = model.fileURL(for: page), let image = UIImage(contentsOfFile: url.path) {
            zoomableImage(Image(uiImage: image).resizable())
        } else if page.assetKind == .image, let remoteURL = page.remoteURL, let url = URL(string: remoteURL) {
            ReaderRemoteImageView(
                url: url,
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
    let url: URL
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
                policy: forceRefresh ? .reloadIgnoringCache : .returnCacheElseLoad
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

    func prefetch(_ urls: [URL], chapterID: String) async {
        _ = chapterID
        for url in urls {
            if Task.isCancelled {
                return
            }
            if inFlight[url] != nil {
                continue
            }
            Task {
                guard !Task.isCancelled else { return }
                _ = try? await image(for: url, forceRefresh: false)
            }
        }
    }

    func clear() async {
        inFlight.removeAll()
        await cache.clear(.image)
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
