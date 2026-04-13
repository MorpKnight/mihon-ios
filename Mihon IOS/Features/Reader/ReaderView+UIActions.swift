//
//  ReaderView+UIActions.swift
//  Mihon IOS
//

import SwiftUI

extension ReaderView {
    func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.18)) {
            showingChrome.toggle()
        }
    }

    func cycleReadingMode() {
        let current = model.state.readerPreferences.mode
        let modes = ReaderMode.allCases
        guard let index = modes.firstIndex(of: current) else { return }
        let next = modes[(index + 1) % modes.count]
        model.setReaderMode(next)
    }

    func cycleOrientation() {
        let current = model.state.readerPreferences.orientation
        let modes = ReaderOrientation.allCases
        guard let index = modes.firstIndex(of: current) else { return }
        let next = modes[(index + 1) % modes.count]
        model.setReaderOrientation(next)
    }

    func toggleSpreadBehavior() {
        let next: ReaderSpreadBehavior = model.state.readerPreferences.spreadBehavior == .fullPage
            ? .autoSplit
            : .fullPage
        model.setReaderSpreadBehavior(next)
    }
}
