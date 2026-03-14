//
//  SettingsViews.swift
//  Mihon IOS
//

import SwiftUI

struct SettingsHomeView: View {
    var body: some View {
        List {
            NavigationLink("Appearance", destination: AppearanceSettingsView())
            NavigationLink("Library", destination: LibrarySettingsView())
            NavigationLink("Reader", destination: ReaderSettingsView())
            NavigationLink("Downloads", destination: DownloadSettingsView())
            NavigationLink("Tracking", destination: TrackingCenterView())
            NavigationLink("Browse", destination: BrowseSettingsView())
            NavigationLink("Data & Storage", destination: DataStorageView())
            NavigationLink("Security", destination: SecuritySettingsView())
            NavigationLink("Advanced", destination: AdvancedSettingsView())
            NavigationLink("Search Settings", destination: SettingsSearchView())
            NavigationLink("About", destination: AboutView())
        }
        .navigationTitle("Settings")
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
                Link("Website", destination: URL(string: "https://mihon.app")!)
                Link("Documentation", destination: URL(string: "https://mihon.app/docs/faq/general")!)
            }
        }
        .navigationTitle("About")
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
