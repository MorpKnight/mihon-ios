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
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .background(
            TabBarControllerAccessor { index in
                handleTabReselect(index: index)
            }
        )
    }

    private func handleTabReselect(index: Int) {
        // The order matches the TabView items above.
        switch index {
        case 0:
            libraryPath = NavigationPath()
        case 1:
            browsePath = NavigationPath()
        case 2:
            historyPath = NavigationPath()
        case 3:
            updatesPath = NavigationPath()
        case 4:
            morePath = NavigationPath()
        default:
            break
        }
    }
}
