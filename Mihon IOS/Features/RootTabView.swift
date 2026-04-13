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
    // Fix #6: Track the previous tab so we can detect a reselect natively
    // without the UIKit TabBarControllerAccessor hack.
    @State private var previousTab: AppTab = .library
    @State private var libraryPath = NavigationPath()
    @State private var browsePath = NavigationPath()
    @State private var historyPath = NavigationPath()
    @State private var updatesPath = NavigationPath()
    @State private var morePath = NavigationPath()

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $libraryPath) {
                LibraryView()
            }
            .tabItem {
                Label("Library", systemImage: "books.vertical")
            }
            .tag(AppTab.library)

            NavigationStack(path: $browsePath) {
                BrowseView()
            }
            .tabItem {
                Label("Browse", systemImage: "safari")
            }
            .tag(AppTab.browse)

            NavigationStack(path: $historyPath) {
                HistoryView()
            }
            .tabItem {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .tag(AppTab.history)

            NavigationStack(path: $updatesPath) {
                UpdatesView()
            }
            .tabItem {
                Label("Updates", systemImage: "sparkles.rectangle.stack")
            }
            .badge(model.unreadUpdatesCount > 0 ? model.unreadUpdatesCount : 0)
            .tag(AppTab.updates)

            NavigationStack(path: $morePath) {
                MoreView()
            }
            .tabItem {
                Label("More", systemImage: "ellipsis.circle")
            }
            .tag(AppTab.more)
        }
        .tint(model.chromeTint)
        // Fix #2: Remove forced `.visible` so iOS can apply the natural
        // edge-to-edge transparency behaviour — the material appears only when
        // scrollable content passes beneath the tab bar.
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        // Fix #6: Native pop-to-root — no UIKit bridging required.
        // When the user taps an already-selected tab, `selectedTab` gets set
        // to the same value it already holds. SwiftUI will fire onChange even
        // for same-value assignments on a TabView selection binding, so we
        // compare against `previousTab` to distinguish a reselect from a
        // genuine tab switch.
        .onChange(of: selectedTab) { old, new in
            if new == old {
                popToRoot(for: new)
            }
            previousTab = new
        }
    }

    private func popToRoot(for tab: AppTab) {
        switch tab {
        case .library:   libraryPath  = NavigationPath()
        case .browse:    browsePath   = NavigationPath()
        case .history:   historyPath  = NavigationPath()
        case .updates:   updatesPath  = NavigationPath()
        case .more:      morePath     = NavigationPath()
        }
    }
}
