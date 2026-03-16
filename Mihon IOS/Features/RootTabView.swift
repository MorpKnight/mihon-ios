//
//  RootTabView.swift
//  Mihon IOS
//

import SwiftUI

private enum AppTab: Hashable {
    case library
    case browse
    case history
    case updates
    case more
}

struct RootTabView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTab: AppTab = .library

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                LibraryView()
            }
            .tabItem {
                Label("Library", systemImage: "books.vertical")
            }
            .tag(AppTab.library)

            NavigationStack {
                BrowseView()
            }
            .tabItem {
                Label("Browse", systemImage: "safari")
            }
            .tag(AppTab.browse)

            NavigationStack {
                HistoryView()
            }
            .tabItem {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .tag(AppTab.history)

            NavigationStack {
                UpdatesView()
            }
            .tabItem {
                Label("Updates", systemImage: "sparkles.rectangle.stack")
            }
            .badge(model.updateFeed.count > 0 ? model.updateFeed.count : 0)
            .tag(AppTab.updates)

            NavigationStack {
                MoreView()
            }
            .tabItem {
                Label("More", systemImage: "ellipsis.circle")
            }
            .tag(AppTab.more)
        }
        .tint(model.chromeTint)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onChange(of: selectedTab) { _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}
