//
//  SettingsViews.swift
//  Mihon IOS
//

import SwiftUI

struct SettingsHomeView: View {
    var body: some View {
        List {
            Section("Core") {
                settingsLink("Appearance", systemImage: "sun.max", destination: AppearanceSettingsView())
                settingsLink("Library", systemImage: "books.vertical", destination: LibrarySettingsView())
                settingsLink("Reader", systemImage: "book.pages", destination: ReaderSettingsView())
                settingsLink("Downloads", systemImage: "arrow.down.circle", destination: DownloadSettingsView())
                settingsLink("Browse", systemImage: "globe", destination: BrowseSettingsView())
            }

            Section("Privacy & Data") {
                settingsLink("Security", systemImage: "faceid", destination: SecuritySettingsView())
                settingsLink("Data & Storage", systemImage: "externaldrive", destination: DataStorageView())
                settingsLink("Tracking", systemImage: "person.badge.clock", destination: TrackingCenterView())
            }

            Section("Support") {
                settingsLink("Advanced", systemImage: "wrench.and.screwdriver", destination: AdvancedSettingsView())
                settingsLink("Search Settings", systemImage: "magnifyingglass", destination: SettingsSearchView())
                settingsLink("About", systemImage: "info.circle", destination: AboutView())
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
    }

    @ViewBuilder
    private func settingsLink<Destination: View>(_ title: String, systemImage: String, destination: Destination) -> some View {
        NavigationLink {
            destination
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

struct AppearanceSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Theme") {
                Toggle("Follow System Appearance", isOn: Binding(
                    get: { model.state.appSettings.useSystemColorScheme },
                    set: model.setUseSystemAppearance
                ))

                if !model.state.appSettings.useSystemColorScheme {
                    Toggle("Prefer Dark Mode", isOn: Binding(
                        get: { model.state.appSettings.prefersDarkMode },
                        set: model.setDarkModePreferred
                    ))
                }
            }

            Section("Language") {
                NavigationLink("App Language", destination: AppLanguageView())
                LabeledContent("Current", value: model.currentLanguageLabel)
            }
        }
        .navigationTitle("Appearance")
    }
}

struct AppLanguageView: View {
    @EnvironmentObject private var model: AppModel
    private let languages = ["system", "en", "id", "ja"]

    var body: some View {
        List {
            ForEach(languages, id: \.self) { code in
                Button {
                    model.setAppLanguageCode(code)
                } label: {
                    HStack {
                        Text(code == "system" ? "System Default" : code.uppercased())
                        Spacer()
                        if model.state.appSettings.appLanguageCode == code {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        .navigationTitle("App Language")
    }
}

struct DownloadSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Queue") {
                Picker("Queue Policy", selection: Binding(
                    get: { model.state.downloadPreferences.queueStrategy },
                    set: model.setDownloadQueueStrategy
                )) {
                    ForEach(DownloadQueueStrategy.allCases) { strategy in
                        Text(strategy.title).tag(strategy)
                    }
                }

                Toggle("Wi-Fi only", isOn: Binding(
                    get: { model.state.downloadPreferences.wifiOnly },
                    set: model.setDownloadWifiOnly
                ))
            }

            Section("Automatic Downloads") {
                Toggle("Auto-download new chapters", isOn: Binding(
                    get: { model.state.downloadPreferences.autoDownloadNewChapters },
                    set: model.setAutoDownloadNewChapters
                ))

                Toggle("Unread chapters only", isOn: Binding(
                    get: { model.state.downloadPreferences.unreadOnly },
                    set: model.setAutoDownloadUnreadOnly
                ))
                .disabled(!model.state.downloadPreferences.autoDownloadNewChapters)
            }

            Section("Storage") {
                LabeledContent("Storage Path", value: "On My iPhone / Mihon")
                LabeledContent("Local Runtime", value: model.localImportSummary())
            }
        }
        .navigationTitle("Downloads")
    }
}

struct BrowseSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Source Visibility") {
                Toggle("Hide adult sources", isOn: Binding(
                    get: { model.state.browsePreferences.hideAdultSources },
                    set: model.setHideAdultSources
                ))
                Toggle("Enabled sources only", isOn: Binding(
                    get: { model.state.browsePreferences.enabledSourcesOnly },
                    set: model.setEnabledSourcesOnly
                ))
                Toggle("Pinned sources only", isOn: Binding(
                    get: { model.state.browsePreferences.pinnedSourcesOnly },
                    set: model.setPinnedSourcesOnly
                ))
            }

            Section("Languages") {
                ForEach(SourceLanguage.allCases) { language in
                    Toggle(language.rawValue, isOn: Binding(
                        get: { model.state.browsePreferences.enabledLanguages.contains(language) },
                        set: { model.setBrowseLanguage(language, enabled: $0) }
                    ))
                }
            }

            Section("Catalog") {
                NavigationLink("Source Repositories", destination: SourceReposView())
                LabeledContent("Visible Sources", value: "\(model.visibleSources.count)")
            }
        }
        .navigationTitle("Browse")
    }
}

struct DataStorageView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section("Backup") {
                NavigationLink("Create Backup", destination: CreateBackupView())
                NavigationLink("Restore Backup", destination: RestoreBackupView())
            }

            Section("Storage") {
                LabeledContent("Summary", value: model.storageSummary())
                LabeledContent("Imports", value: model.localImportSummary())
                LabeledContent("Database", value: "Snapshot JSON + import storage")
                LabeledContent("Image Cache", value: ByteCountFormatter.string(fromByteCount: Int64(model.cacheStats.diskImageBytes), countStyle: .file))
                LabeledContent("Metadata Cache", value: ByteCountFormatter.string(fromByteCount: Int64(model.cacheStats.diskMetadataBytes), countStyle: .file))
                LabeledContent("Network Cache", value: ByteCountFormatter.string(fromByteCount: Int64(model.cacheStats.diskNetworkBytes), countStyle: .file))
            }

            Section("Maintenance") {
                Button("Clear History", role: .destructive) {
                    model.clearHistory()
                }
                Button("Clear Reading Progress", role: .destructive) {
                    model.clearProgress()
                }
                Button("Clear Notes", role: .destructive) {
                    model.clearNotes()
                }
                Button("Clear Image Cache", role: .destructive) {
                    Task { await model.clearImageCache() }
                }
                Button("Clear Source Metadata Cache", role: .destructive) {
                    Task { await model.clearSourceMetadataCache() }
                }
                Button("Clear All Caches", role: .destructive) {
                    Task { await model.clearAllCaches() }
                }
            }
        }
        .navigationTitle("Data & Storage")
    }
}

struct SecuritySettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Privacy") {
                Toggle("Incognito Mode", isOn: Binding(
                    get: { model.state.appSettings.incognitoMode },
                    set: model.setIncognitoMode
                ))
                Toggle("Lock with Face ID", isOn: Binding(
                    get: { model.state.securityPreferences.requireBiometricUnlock },
                    set: model.setBiometricUnlockEnabled
                ))
                Toggle("Blur in App Switcher", isOn: Binding(
                    get: { model.state.securityPreferences.blurAppSwitcher },
                    set: model.setBlurAppSwitcher
                ))
                Toggle("Hide Sensitive Covers", isOn: Binding(
                    get: { model.state.securityPreferences.hideSensitiveCovers },
                    set: model.setHideSensitiveCovers
                ))
            }

            Section("Library Protection") {
                Toggle("Lock library edits", isOn: Binding(
                    get: { model.state.securityPreferences.lockLibraryEdits },
                    set: model.setLockLibraryEdits
                ))
                Text("When enabled, category editing and quick delete actions are disabled.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Security")
    }
}

struct AdvancedSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Reader Networking") {
                Stepper(
                    "Image prefetch window: \(model.state.advancedPreferences.imagePrefetchCount)",
                    value: Binding(
                        get: { model.state.advancedPreferences.imagePrefetchCount },
                        set: model.setImagePrefetchCount
                    ),
                    in: 0...6
                )

                Toggle("Aggressive image retry", isOn: Binding(
                    get: { model.state.advancedPreferences.aggressiveImageRetry },
                    set: model.setAggressiveImageRetry
                ))
            }

            Section("Cache Limits") {
                Stepper(
                    "Memory cache: \(model.state.advancedPreferences.memoryCacheLimitMB) MB",
                    value: Binding(
                        get: { model.state.advancedPreferences.memoryCacheLimitMB },
                        set: model.setMemoryCacheLimitMB
                    ),
                    in: 20...200,
                    step: 20
                )

                Stepper(
                    "Image count limit: \(model.state.advancedPreferences.imageCacheCountLimit)",
                    value: Binding(
                        get: { model.state.advancedPreferences.imageCacheCountLimit },
                        set: model.setImageCacheCountLimit
                    ),
                    in: 40...200,
                    step: 20
                )

                LabeledContent("In-memory images", value: "\(model.cacheStats.memoryImageCount)")
                LabeledContent("In-memory data", value: "\(model.cacheStats.memoryDataCount)")
            }

            Section("History") {
                Stepper(
                    "History limit: \(model.state.advancedPreferences.historyLimit)",
                    value: Binding(
                        get: { model.state.advancedPreferences.historyLimit },
                        set: model.setHistoryLimit
                    ),
                    in: 20...500,
                    step: 20
                )
            }

            Section("Diagnostics") {
                Toggle("Show diagnostics", isOn: Binding(
                    get: { model.state.advancedPreferences.showDiagnostics },
                    set: model.setShowDiagnostics
                ))

                NavigationLink("Open Error Logs", destination: DiagnosticsLogView())

                if model.state.advancedPreferences.showDiagnostics {
                    ForEach(model.diagnosticsSummary(), id: \.self) { line in
                        Text(line)
                            .font(.footnote.monospaced())
                    }
                }
            }

            Section("App State") {
                Button("Show onboarding again") {
                    model.resetOnboarding()
                }
            }
        }
        .navigationTitle("Advanced")
    }
}

struct DiagnosticsLogView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section("Summary") {
                ForEach(model.diagnosticsSummary(), id: \.self) { line in
                    Text(line)
                        .font(.footnote.monospaced())
                }

                Button("Clear Logs", role: .destructive) {
                    model.clearDiagnostics()
                }
                .disabled(model.diagnosticLogs.isEmpty)
            }

            Section("Entries") {
                if model.diagnosticLogs.isEmpty {
                    ContentUnavailableView(
                        "No Error Logs",
                        systemImage: "checkmark.circle",
                        description: Text("New source, reader, repo, and security failures will appear here.")
                    )
                } else {
                    ForEach(model.diagnosticLogs) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(entry.title)
                                    .font(.headline)
                                Spacer()
                                Text(entry.kind.rawValue.uppercased())
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            Text(entry.message)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if !entry.metadata.isEmpty {
                                ForEach(entry.metadata.keys.sorted(), id: \.self) { key in
                                    if let value = entry.metadata[key] {
                                        LabeledContent(key, value: value)
                                            .font(.caption.monospaced())
                                    }
                                }
                            }

                            Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Error Logs")
    }
}

struct SettingsSearchView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""

    private var entries: [(String, String)] {
        [
            ("Follow System Appearance", model.state.appSettings.useSystemColorScheme ? "On" : "Off"),
            ("Prefer Dark Mode", model.state.appSettings.prefersDarkMode ? "On" : "Off"),
            ("App Language", model.currentLanguageLabel),
            ("Default Category", model.categoryName(for: model.state.libraryPreferences.defaultCategoryID)),
            ("Library Sort", model.state.libraryPreferences.sortMode.title),
            ("Show Continue Reading", model.state.libraryPreferences.showContinueReading ? "On" : "Off"),
            ("Downloaded Badge", model.state.libraryPreferences.showDownloadedBadge ? "On" : "Off"),
            ("Unread Badge", model.state.libraryPreferences.showUnreadBadge ? "On" : "Off"),
            ("Download Queue", model.state.downloadPreferences.queueStrategy.title),
            ("Wi-Fi only", model.state.downloadPreferences.wifiOnly ? "On" : "Off"),
            ("Auto-download", model.state.downloadPreferences.autoDownloadNewChapters ? "On" : "Off"),
            ("Hide adult sources", model.state.browsePreferences.hideAdultSources ? "On" : "Off"),
            ("Incognito Mode", model.state.appSettings.incognitoMode ? "On" : "Off"),
            ("Blur in App Switcher", model.state.securityPreferences.blurAppSwitcher ? "On" : "Off"),
            ("Image Prefetch Window", "\(model.state.advancedPreferences.imagePrefetchCount)"),
            ("History Limit", "\(model.state.advancedPreferences.historyLimit)"),
        ]
    }

    var body: some View {
        List {
            ForEach(entries.filter { query.isEmpty || $0.0.localizedCaseInsensitiveContains(query) }, id: \.0) { entry in
                LabeledContent(entry.0, value: entry.1)
            }
        }
        .searchable(text: $query, prompt: "Find setting")
        .navigationTitle("Search Settings")
    }
}

struct AboutView: View {
    @State private var blockedLinkMessage: String?

    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version) (\(build))"
    }

    var body: some View {
        List {
            Section("App") {
                LabeledContent("Name", value: "Mihon iOS")
                LabeledContent("Version", value: versionLabel)
                NavigationLink("Open Source Licenses", destination: LicensesView())
            }

            Section("Links") {
                Button("Website") {
                    blockedLinkMessage = "Website belum siap dibuka dari aplikasi. Tautan eksternal masih ditutup sementara."
                }
                .foregroundStyle(.primary)

                Button("Documentation") {
                    blockedLinkMessage = "Documentation belum siap dibuka dari aplikasi. Tautan eksternal masih ditutup sementara."
                }
                .foregroundStyle(.primary)
            }
        }
        .navigationTitle("About")
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

struct LicensesView: View {
    var body: some View {
        List {
            NavigationLink("SwiftUI", destination: LicenseDetailView(title: "SwiftUI", text: "Apple UI framework used for the iOS port."))
            NavigationLink("Foundation", destination: LicenseDetailView(title: "Foundation", text: "System framework used for model and persistence plumbing."))
        }
        .navigationTitle("Licenses")
    }
}

private struct LicenseDetailView: View {
    let title: String
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(title)
    }
}

struct CreateBackupView: View {
    @EnvironmentObject private var model: AppModel
    @State private var includeTrackers = true
    @State private var includeHistory = true
    @State private var includePreferences = true

    var body: some View {
        Form {
            Section("Scope") {
                Toggle("Include trackers", isOn: $includeTrackers)
                Toggle("Include history", isOn: $includeHistory)
                Toggle("Include preferences", isOn: $includePreferences)
            }

            Section("Preview") {
                let payload = model.createPayload()
                LabeledContent("Items", value: "\(payload.itemCount)")
                LabeledContent("Created", value: payload.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .navigationTitle("Create Backup")
    }
}

struct RestoreBackupView: View {
    var body: some View {
        List {
            Text("Backup restore flow should accept exported files, validate schema, and support merge or replace behavior.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Restore Backup")
    }
}
