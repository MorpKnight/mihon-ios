//
//  MangaCoverView.swift
//  Mihon IOS
//

import SwiftUI
import Foundation

struct MangaCoverView: View {
    let manga: Manga
    let hideSensitiveCover: Bool
    let allowsAdultContent: Bool
    var cornerRadius: CGFloat = 16
    var overlaySystemImage: String? = nil

    init(
        manga: Manga,
        hideSensitiveCover: Bool = false,
        allowsAdultContent: Bool = false,
        cornerRadius: CGFloat = 16,
        overlaySystemImage: String? = nil
    ) {
        self.manga = manga
        self.hideSensitiveCover = hideSensitiveCover
        self.allowsAdultContent = allowsAdultContent
        self.cornerRadius = cornerRadius
        self.overlaySystemImage = overlaySystemImage
    }

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
                    CachedCoverImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
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
        hideSensitiveCover && allowsAdultContent
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

private struct CachedCoverImage<Content: View>: View {
    let url: URL
    @ViewBuilder let content: (Image) -> Content

    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let uiImage {
                content(Image(uiImage: uiImage))
            } else {
                Rectangle()
                    .fill(.clear)
                    .task(id: url) {
                        await load()
                    }
            }
        }
    }

    @MainActor
    private func load() async {
        do {
            let image = try await AppCacheController.shared.image(
                for: url,
                key: "cover-image|\(url.absoluteString)",
                policy: .returnCacheElseLoad,
                intent: .thumbnail
            ) {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                    throw URLError(.badServerResponse)
                }
                return data
            }
            uiImage = image
        } catch {
            uiImage = nil
        }
    }
}
