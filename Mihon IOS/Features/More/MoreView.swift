//
//  MoreView.swift
//  Mihon IOS
//

import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section("Modes") {
                Toggle("Downloaded Only", isOn: Binding(
                    get: { model.state.appSettings.downloadedOnly },
                    set: model.setDownloadedOnly
                ))

                Toggle("Incognito Mode", isOn: Binding(
                    get: { model.state.appSettings.incognitoMode },
                    set: model.setIncognitoMode
                ))
            }

            Section("Tools") {
                NavigationLink {
                    DownloadQueueView()
                } label: {
                    Label("Download Queue", systemImage: "arrow.down.circle")
                }

                NavigationLink {
                    CategoryManagementView()
                } label: {
                    Label("Categories", systemImage: "folder")
                }

                NavigationLink {
                    StatsView()
                } label: {
                    Label("Stats", systemImage: "chart.bar")
                }

                NavigationLink {
                    DataStorageView()
                } label: {
                    Label("Data & Storage", systemImage: "externaldrive")
                }

                NavigationLink {
                    DiagnosticsLogView()
                } label: {
                    Label("Error Logs", systemImage: "exclamationmark.bubble")
                }
            }

            Section("Settings & About") {
                NavigationLink {
                    SettingsHomeView()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }

                NavigationLink {
                    AboutView()
                } label: {
                    Label("About", systemImage: "info.circle")
                }

                Link(destination: URL(string: "https://mihon.app/docs/faq/general")!) {
                    Label("Help", systemImage: "questionmark.circle")
                }

                Link(destination: URL(string: "https://mihon.app")!) {
                    Label("Donate", systemImage: "heart.circle")
                }
            }
        }
        .navigationTitle("More")
    }
}
