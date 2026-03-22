//
//  ReaderView+PageStateUpdates.swift
//  Mihon IOS
//

import SwiftUI

extension ReaderView {
    func registerImageSize(_ size: CGSize, for pageID: String) {
        guard size.width > 0, size.height > 0 else { return }
        let rounded = CGSize(width: size.width.rounded(.toNearestOrAwayFromZero), height: size.height.rounded(.toNearestOrAwayFromZero))
        if let existing = pageImageSizes[pageID], existing == rounded {
            return
        }

        var updatedSizes = pageImageSizes
        updatedSizes[pageID] = rounded
        pageImageSizes = updatedSizes
        refreshCommittedSnapshot(preferredPageIndex: deferredResumePageIndex, animatedSync: false)
    }

    func updateSurfaceInteractionState(_ state: ReaderInteractionState, for itemID: String) {
        if surfaceInteractionStates[itemID] == state {
            return
        }
        surfaceInteractionStates[itemID] = state
    }

    func registerPageLuminance(_ luminance: CGFloat, for itemID: String) {
        let bounded = min(max(luminance, 0), 1)
        if pageLuminanceByRenderItemID[itemID] == bounded {
            return
        }
        pageLuminanceByRenderItemID[itemID] = bounded
    }
}
