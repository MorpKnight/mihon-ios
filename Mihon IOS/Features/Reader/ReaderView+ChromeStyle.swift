//
//  ReaderView+ChromeStyle.swift
//  Mihon IOS
//

import SwiftUI

extension ReaderView {
    var readerBarBackground: some ShapeStyle {
        if readerChromeIsBrightMode {
            return AnyShapeStyle(.regularMaterial)
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }

    var readerChromeLuminance: CGFloat {
        guard !isVerticalReader,
              pagerItems.indices.contains(pagerDisplayIndex),
              case .render(let item) = pagerItems[pagerDisplayIndex],
              let luminance = pageLuminanceByRenderItemID[item.id] else {
            return 0.5
        }
        return luminance
    }

    var readerChromeIsBrightMode: Bool {
        readerChromeLuminance > 0.62
    }

    var readerChromeForegroundColor: Color {
        readerChromeIsBrightMode ? .black.opacity(0.9) : .white
    }

    var readerPillTintColor: Color {
        readerChromeIsBrightMode ? .black : .white
    }

    var readerPillRegularOpacity: Double {
        readerChromeIsBrightMode ? 0.1 : 0.08
    }

    var readerPillProminentOpacity: Double {
        readerChromeIsBrightMode ? 0.2 : 0.18
    }

    var readerCapsuleBackground: some ShapeStyle {
        Color.white.opacity(0.14)
    }

    var readingModeSymbol: String {
        switch activeReaderMode {
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

    var orientationSymbol: String {
        switch model.state.readerPreferences.orientation {
        case .system:
            return "iphone"
        case .portrait:
            return "iphone"
        case .landscape:
            return "iphone.landscape"
        }
    }

    var spreadBehaviorTitle: String {
        switch model.state.readerPreferences.spreadBehavior {
        case .fullPage:
            return "Full"
        case .autoSplit:
            return "Split"
        }
    }

    var spreadBehaviorSymbol: String {
        switch model.state.readerPreferences.spreadBehavior {
        case .fullPage:
            return "rectangle"
        case .autoSplit:
            return "rectangle.split.1x2"
        }
    }

    var chapterLeadingIcon: String {
        isRTLPager ? "chevron.right" : "chevron.left"
    }

    var chapterTrailingIcon: String {
        isRTLPager ? "chevron.left" : "chevron.right"
    }
}
