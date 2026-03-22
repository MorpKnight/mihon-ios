//
//  ReaderView.swift
//  Mihon IOS
//

import SwiftUI
import UIKit

struct ReaderView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    let manga: Manga
    let initialChapter: Chapter
    let imagePipeline: ReaderImagePipelining

    @State var currentChapter: Chapter
    @State var pageIndex: Int
    @State private var showingSettings = false
    @State private var showingActions = false
    @State var showingChrome = false
    @State var pageLoadState: ReaderContentLoadState = .idle
    @State var retryTick = 0
    @State var pendingPageIndexAfterChapterChange: Int?
    @State var activeLoadRequestID = UUID()
    @State var prefetchTask: Task<Void, Never>?
    @State var hasAppliedResumeProgress = false
    @State var canPersistPageProgress = false
    @State var pagerDisplayIndex = 1
    @State var pageImageSizes: [String: CGSize] = [:]
    @State var deferredResumePageIndex: Int?
    @State var surfaceInteractionStates: [String: ReaderInteractionState] = [:]
    @State var transitionState: ReaderTransitionState?
    @State var isChapterTransitioning = false
    @State var pendingVerticalScrollTarget: Int?
    @State var committedSnapshot: ReaderContentSnapshot?
    @State var deferredSnapshot: ReaderContentSnapshot?
    @State var deferredSnapshotPreferredPageIndex: Int?
    @State var readerInteractionPhase: ReaderInteractionPhase = .idle
    @State var pagerSettleTask: Task<Void, Never>?
    @State private var exactPagerWidth: CGFloat = 0
    @State var pageLuminanceByRenderItemID: [String: CGFloat] = [:]

    private let verticalScrollCoordinateSpace = "reader.vertical.scroll"
    static let chapterEndPageTarget = Int.max

    init(
        manga: Manga,
        initialChapter: Chapter,
        imagePipeline: ReaderImagePipelining = ReaderImagePipeline.shared
    ) {
        self.manga = manga
        self.initialChapter = initialChapter
        self.imagePipeline = imagePipeline
        _currentChapter = State(initialValue: initialChapter)
        _pageIndex = State(initialValue: 0)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geometry in
                readerBody(in: geometry.size)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                handleTap(at: value.location, in: geometry.size)
                            }
                    )
                    .onAppear {
                        exactPagerWidth = max(geometry.size.width, 1)
                    }
                    .onChange(of: geometry.size.width) { _, newWidth in
                        exactPagerWidth = max(newWidth, 1)
                    }
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
            pageLuminanceByRenderItemID = [:]
            transitionState = nil
            pendingVerticalScrollTarget = nil
            committedSnapshot = nil
            deferredSnapshot = nil
            deferredSnapshotPreferredPageIndex = nil
            readerInteractionPhase = .idle
            pagerSettleTask?.cancel()
            pagerSettleTask = nil
            pageIndex = pendingPageIndexAfterChapterChange ?? 0
            hasAppliedResumeProgress = false
            startPageLoad(forceRefresh: false)
        }
        .onChange(of: model.state.readerPreferences.mode) { _, _ in
            refreshCommittedSnapshot(preferredPageIndex: nil, animatedSync: false)
        }
        .onChange(of: model.state.readerPreferences.spreadBehavior) { _, _ in
            refreshCommittedSnapshot(preferredPageIndex: nil, animatedSync: false)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, canPersistPageProgress, !logicalPages.isEmpty { persistProgress() }
        }
        .onDisappear {
            activeLoadRequestID = UUID()
            prefetchTask?.cancel()
            pagerSettleTask?.cancel()
            prefetchTask = nil
            Task {
                await imagePipeline.cancelWindow(for: currentChapter.id)
            }
        }
    }

    @ViewBuilder
    private func readerBody(in rootSize: CGSize) -> some View {
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
        } else if activeReaderMode == .vertical || activeReaderMode == .webtoon {
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
                                    imagePipeline: imagePipeline,
                                    item: item,
                                    filter: model.state.readerPreferences.colorFilter,
                                    fillViewport: false,
                                    allowsImagePan: false,
                                    allowsHighDetailAtRest: true,
                                    onImageMetadataResolved: { size in
                                        registerImageSize(size, for: item.page.id)
                                    },
                                    onLuminanceResolved: { _ in
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
            pagedReaderBody(width: max(exactPagerWidth > 0 ? exactPagerWidth : rootSize.width, 1))
            .ignoresSafeArea()
        }
    }

    private func pagedReaderBody(width: CGFloat) -> some View {
        let pageWidth = max(width, 1)
        return ReaderPagedContainer(
            currentIndex: $pagerDisplayIndex,
            itemCount: pagerItems.count,
            pageWidth: pageWidth,
            allowsInteractivePaging: allowsInteractivePagerDragging,
            shouldCaptureDrag: { translationWidth, translationHeight in
                shouldCapturePagerDrag(translationWidth: translationWidth, translationHeight: translationHeight)
            },
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
                                imagePipeline: imagePipeline,
                                item: renderItem,
                                filter: model.state.readerPreferences.colorFilter,
                                fillViewport: true,
                                allowsImagePan: true,
                                allowsHighDetailAtRest: true,
                                onImageMetadataResolved: { size in
                                    registerImageSize(size, for: renderItem.page.id)
                                },
                                onLuminanceResolved: { luminance in
                                    registerPageLuminance(luminance, for: renderItem.id)
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
                title: activeReaderMode.title,
                isProminent: true,
                foregroundColor: readerChromeForegroundColor,
                backgroundTint: readerPillTintColor,
                regularBackgroundOpacity: readerPillRegularOpacity,
                prominentBackgroundOpacity: readerPillProminentOpacity
            ) {
                cycleReadingMode()
            }

            if !isVerticalReader {
                ReaderBottomPill(
                    systemImage: spreadBehaviorSymbol,
                    title: spreadBehaviorTitle,
                    foregroundColor: readerChromeForegroundColor,
                    backgroundTint: readerPillTintColor,
                    regularBackgroundOpacity: readerPillRegularOpacity,
                    prominentBackgroundOpacity: readerPillProminentOpacity
                ) {
                    toggleSpreadBehavior()
                }
            }

            ReaderBottomPill(
                systemImage: orientationSymbol,
                title: model.state.readerPreferences.orientation.rawValue.capitalized,
                foregroundColor: readerChromeForegroundColor,
                backgroundTint: readerPillTintColor,
                regularBackgroundOpacity: readerPillRegularOpacity,
                prominentBackgroundOpacity: readerPillProminentOpacity
            ) {
                cycleOrientation()
            }

            ReaderBottomPill(
                systemImage: model.state.readerPreferences.showPageNumber ? "number.circle.fill" : "number.circle",
                title: "Page",
                foregroundColor: readerChromeForegroundColor,
                backgroundTint: readerPillTintColor,
                regularBackgroundOpacity: readerPillRegularOpacity,
                prominentBackgroundOpacity: readerPillProminentOpacity
            ) {
                model.setReaderPageNumberVisible(!model.state.readerPreferences.showPageNumber)
            }

            ReaderBottomPill(
                systemImage: "slider.horizontal.3",
                title: "Settings",
                foregroundColor: readerChromeForegroundColor,
                backgroundTint: readerPillTintColor,
                regularBackgroundOpacity: readerPillRegularOpacity,
                prominentBackgroundOpacity: readerPillProminentOpacity
            ) {
                showingSettings = true
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(readerBarBackground, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 12)
    }

    private func handleTap(at point: CGPoint, in size: CGSize) {
        guard !isNavigationSuspended else { return }
        let zone = ReaderTapZone.resolve(point: point, in: size)
        let intent = zone.intent(isRTLPager: isRTLPager)
        if let transitionDirection = currentPagerTransitionDirection {
            handleTransitionTap(intent: intent, transitionDirection: transitionDirection)
            return
        }
        switch intent {
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


    

    func boundedPageIndex(for index: Int) -> Int {
        min(max(index, 0), max(logicalPages.count - 1, 0))
    }



}
