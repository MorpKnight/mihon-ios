//
//  MoreView.swift
//  Mihon IOS
//

import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var model: AppModel
    @State private var blockedLinkMessage: String?

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
                    DownloadsView()
                } label: {
                    Label("Downloads", systemImage: "arrow.down.circle")
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

                Button {
                    blockedLinkMessage = "Help belum siap. Tautan eksternal masih ditutup sementara."
                } label: {
                    Label("Help", systemImage: "questionmark.circle")
                }
                .foregroundStyle(.primary)

                Button {
                    blockedLinkMessage = "Donate belum siap. Tautan eksternal masih ditutup sementara."
                } label: {
                    Label("Donate", systemImage: "heart.circle")
                }
                .foregroundStyle(.primary)
            }
        }
        .navigationTitle("More")
        .alert("Coming Soon", isPresented: Binding(
            get: { blockedLinkMessage != nil },
            set: { if !$0 { blockedLinkMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                blockedLinkMessage = nil
            }
        } message: {
            Text(blockedLinkMessage ?? "")
        }
    }
}
