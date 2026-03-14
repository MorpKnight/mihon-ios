//
//  SourceCatalogViews.swift
//  Mihon IOS
//

import SwiftUI

struct SourceCatalogView: View {
    @EnvironmentObject private var model: AppModel
    @State private var trustedOnly = false

    private var items: [SourceCatalogItem] {
        model.sourceCatalogItems().filter { !trustedOnly || $0.isTrusted }
    }

    var body: some View {
        List {
            Section {
                Toggle("Trusted only", isOn: $trustedOnly)

                NavigationLink {
                    SourceReposView()
                } label: {
                    Label("Repository URLs", systemImage: "link")
                }
            }

            Section("Catalog Packages") {
                ForEach(items) { item in
                    NavigationLink {
                        SourceCatalogDetailView(item: item)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.title)
                                    .font(.headline)
                                Spacer()
                                if item.hasUpdate {
                                    Text("Update")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.orange)
                                }
                            }
                            Text(item.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("v\(item.version) • \(item.isInstalled ? "Installed" : "Available")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Source Catalog")
    }
}

struct SourceCatalogDetailView: View {
    let item: SourceCatalogItem

    var body: some View {
        List {
            Section("Package") {
                LabeledContent("Version", value: item.version)
                LabeledContent("Trust", value: item.isTrusted ? "Trusted" : "Untrusted")
                LabeledContent("Status", value: item.isInstalled ? "Installed" : "Available")
            }

            Section("Included Sources") {
                ForEach(item.sources) { source in
                    NavigationLink {
                        SourcePreferencesView(source: source)
                    } label: {
                        Label(source.name, systemImage: source.systemImage)
                    }
                }
            }
        }
        .navigationTitle(item.title)
    }
}

struct SourcePreferencesView: View {
    @EnvironmentObject private var model: AppModel

    let source: Source

    var body: some View {
        List {
            ForEach(model.sourcePreferences(for: source)) { preference in
                LabeledContent(preference.title, value: preference.value)
            }
        }
        .navigationTitle("\(source.name) Settings")
    }
}

struct SourceReposView: View {
    @EnvironmentObject private var model: AppModel
    @State private var repoURL = ""

    var body: some View {
        List {
            Section("Add Repository") {
                TextField("https://repo.example.com/index.json", text: $repoURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button("Add Repo") {
                    model.addSourceRepo(repoURL)
                    repoURL = ""
                }
            }

            Section("Current Repositories") {
                ForEach(model.state.sourceRepos, id: \.self) { repo in
                    HStack {
                        Text(repo)
                            .font(.subheadline)
                        Spacer()
                        Button(role: .destructive) {
                            model.removeSourceRepo(repo)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Source Repos")
    }
}

struct SourceWebView: View {
    @EnvironmentObject private var model: AppModel
    let source: Source

    var body: some View {
        List {
            Section("External Browser") {
                if let url = model.sourceWebURL(for: source) {
                    Link("Open \(source.name)", destination: url)
                }
            }

            Section("Compatibility") {
                Text("Android WebView flows such as auth, captcha, and share intents should be adapted to iOS-native browser or in-app web session handling.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Web Source")
    }
}
