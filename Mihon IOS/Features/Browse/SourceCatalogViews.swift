//
//  SourceCatalogViews.swift
//  Mihon IOS
//

import SwiftUI

struct SourceCatalogView: View {
    @EnvironmentObject private var model: AppModel
    @State private var trustedOnly = false
    @State private var selectedLanguageFilter = "preferred"

    private var items: [SourceCatalogItem] {
        model.catalogItems(matchingLanguageFilter: selectedLanguageFilter)
            .filter { !trustedOnly || $0.isTrusted }
    }

    var body: some View {
        List {
            Section {
                Toggle("Trusted only", isOn: $trustedOnly)

                Picker("Language Filter", selection: $selectedLanguageFilter) {
                    ForEach(model.sourceCatalogLanguageFilters(), id: \.id) { filter in
                        Text(filter.title).tag(filter.id)
                    }
                }

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
                                Text(item.supportStatus.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(badgeColor(for: item.supportStatus))
                                if item.hasUpdate {
                                    Text("Update")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.orange)
                                }
                            }
                            Text(item.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("v\(item.version) • \(item.originLabel) • \(item.isInstalled ? "Installed" : "Available")")
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
    @EnvironmentObject private var model: AppModel
    let item: SourceCatalogItem

    var body: some View {
        List {
            Section("Package") {
                LabeledContent("Version", value: item.version)
                LabeledContent("Trust", value: item.isTrusted ? "Trusted" : "Untrusted")
                LabeledContent("Status", value: item.isInstalled ? "Installed" : "Available")
                LabeledContent("Runtime", value: item.supportStatus.title)
                LabeledContent("Origin", value: item.originLabel)
                if !item.languageCodes.isEmpty {
                    LabeledContent("Languages", value: item.languageCodes.map(model.languageFilterTitle(for:)).joined(separator: ", "))
                }
            }

            Section("Included Sources") {
                ForEach(item.sources) { source in
                    NavigationLink {
                        SourcePreferencesView(source: source)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(source.name, systemImage: source.systemImage)
                            Text(model.descriptor(for: source.id)?.engineFamily.title ?? source.engineFamily.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
            if let descriptor = model.descriptor(for: source.id) {
                Section("Runtime Descriptor") {
                    LabeledContent("Family", value: descriptor.engineFamily.title)
                    LabeledContent("Runtime", value: descriptor.supportStatus.title)
                    if let baseURL = descriptor.baseURL {
                        LabeledContent("Base URL", value: baseURL)
                    }
                    if let packageName = descriptor.packageName {
                        LabeledContent("Package", value: packageName)
                    }
                    if let version = descriptor.version {
                        LabeledContent("Version", value: version)
                    }
                    LabeledContent("Capabilities", value: descriptor.capabilities.map(\.rawValue).sorted().joined(separator: ", "))
                    if !descriptor.featureFlags.isEmpty {
                        LabeledContent("Feature Flags", value: descriptor.featureFlags.joined(separator: ", "))
                    }
                }

                if !descriptor.filterSchema.isEmpty {
                    Section("Filter Schema") {
                        ForEach(descriptor.filterSchema) { filter in
                            LabeledContent(filter.title, value: filter.kind)
                        }
                    }
                }
            }

            Section("Source Preferences") {
            ForEach(model.sourcePreferences(for: source)) { preference in
                LabeledContent(preference.title, value: preference.value)
            }
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
                    let value = repoURL
                    repoURL = ""
                    Task {
                        await model.addSourceRepo(value)
                    }
                }
                .disabled(repoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.importingRepoURL != nil)

                if let importing = model.importingRepoURL {
                    LabeledContent("Importing", value: importing)
                        .font(.caption)
                }

                if let error = model.repoImportErrorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Current Repositories") {
                if !model.repoRecords.isEmpty {
                    Button("Refresh All") {
                        Task {
                            await model.refreshAllSourceRepos()
                        }
                    }
                    .disabled(model.importingRepoURL != nil)
                }

                ForEach(model.repoRecords) { repo in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(repo.title)
                                    .font(.headline)
                                Text(repo.url)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(repo.importedSources.count) imported source(s)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                Task {
                                    await model.refreshSourceRepo(repo.url)
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.plain)
                            .disabled(model.importingRepoURL != nil)

                            Button(role: .destructive) {
                                model.removeSourceRepo(repo.url)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }

                        if let error = repo.lastError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else {
                            let liveCount = repo.importedSources.filter { $0.supportStatus == .live }.count
                            let plannedCount = repo.importedSources.filter { $0.supportStatus == .planned }.count
                            Text("\(liveCount) live • \(plannedCount) planned • Updated \(repo.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Source Repos")
    }
}

private func badgeColor(for status: SourceSupportStatus) -> Color {
    switch status {
    case .live:
        return .green
    case .planned:
        return .orange
    case .unsupported:
        return .red
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
