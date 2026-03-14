//
//  MangaCoverView.swift
//  Mihon IOS
//

import SwiftUI

struct MangaCoverView: View {
    @EnvironmentObject private var model: AppModel
    let manga: Manga
    var cornerRadius: CGFloat = 16
    var overlaySystemImage: String? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: manga.coverHexes.map(Color.init(hex:)),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                if shouldHideCover {
                    hiddenCoverOverlay
                } else if let coverURL = manga.coverURL, let url = URL(string: coverURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            gradientOverlay
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            gradientOverlay
                        @unknown default:
                            gradientOverlay
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                } else {
                    gradientOverlay
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let overlaySystemImage {
                    Image(systemName: overlaySystemImage)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(8)
                }
            }
            .clipped()
    }

    private var gradientOverlay: some View {
        LinearGradient(
            colors: manga.coverHexes.map(Color.init(hex:)),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var shouldHideCover: Bool {
        model.state.securityPreferences.hideSensitiveCovers &&
        (model.source(for: manga.sourceID)?.allowsAdultContent ?? false)
    }

    private var hiddenCoverOverlay: some View {
        ZStack {
            gradientOverlay.blur(radius: 12)
            VStack(spacing: 6) {
                Image(systemName: "eye.slash.fill")
                    .font(.caption)
                Text("Hidden")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white.opacity(0.9))
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
