//
//  ReaderUIComponents.swift
//  Mihon IOS
//

import SwiftUI

struct ReaderChromeButton: View {
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

struct ReaderPagedContainer<Content: View>: View {
    @Binding var currentIndex: Int
    let itemCount: Int
    let pageWidth: CGFloat
    let allowsInteractivePaging: Bool
    let shouldCaptureDrag: (CGFloat, CGFloat) -> Bool
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat, CGFloat, CGFloat) -> Void
    @ViewBuilder let content: Content

    @GestureState private var dragTranslation: CGFloat = 0

    var body: some View {
        GeometryReader { _ in
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .offset(x: -CGFloat(currentIndex) * pageWidth + (allowsInteractivePaging ? dragTranslation : 0))
                .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.9), value: currentIndex)
                .contentShape(Rectangle())
                .clipped()
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12, coordinateSpace: .local)
                        .updating($dragTranslation) { value, state, _ in
                            guard shouldCaptureDrag(value.translation.width, value.translation.height) else { return }
                            state = allowsInteractivePaging ? value.translation.width : 0
                        }
                        .onChanged { value in
                            guard shouldCaptureDrag(value.translation.width, value.translation.height) else { return }
                            onDragChanged(value.translation.width)
                        }
                        .onEnded { value in
                            guard shouldCaptureDrag(value.translation.width, value.translation.height) else { return }
                            onDragChanged(0)
                            onDragEnded(value.translation.width, value.predictedEndTranslation.width, pageWidth)
                        }
                )
        }
    }
}

struct ReaderTransitionPage: View {
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

struct ReaderBottomPill: View {
    let systemImage: String
    let title: String
    var isProminent: Bool = false
    var foregroundColor: Color = .white
    var backgroundTint: Color = .white
    var regularBackgroundOpacity: Double = 0.08
    var prominentBackgroundOpacity: Double = 0.18
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
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var backgroundStyle: some ShapeStyle {
        if isProminent {
            return AnyShapeStyle(backgroundTint.opacity(prominentBackgroundOpacity))
        }
        return AnyShapeStyle(backgroundTint.opacity(regularBackgroundOpacity))
    }
}

struct ReaderVisiblePageFramesPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

enum ReaderTapZone {
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

enum ReaderTapIntent {
    case forward
    case backward
    case toggleChrome
    case none
}

enum ReaderTransitionDirection {
    case previous
    case next
}

struct ReaderTransitionState: Equatable {
    static let activationDistance: CGFloat = 120

    let direction: ReaderTransitionDirection
    let progress: CGFloat
    let isLoading: Bool
}

struct ReaderEmptyState: View {
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
