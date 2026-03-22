//
//  ReaderSettingsView.swift
//  Mihon IOS
//

import SwiftUI

struct ReaderSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    Toggle("Keep screen awake", isOn: Binding(
                        get: { model.state.readerPreferences.keepAwake },
                        set: model.setKeepAwake
                    ))

                    Toggle("Show page number", isOn: Binding(
                        get: { model.state.readerPreferences.showPageNumber },
                        set: model.setReaderPageNumberVisible
                    ))

                    Picker("Orientation", selection: Binding(
                        get: { model.state.readerPreferences.orientation },
                        set: model.setReaderOrientation
                    )) {
                        ForEach(ReaderOrientation.allCases) { orientation in
                            Text(orientation.rawValue.capitalized).tag(orientation)
                        }
                    }
                }

                Section {
                    Picker("Mode", selection: Binding(
                        get: { model.state.readerPreferences.mode },
                        set: model.setReaderMode
                    )) {
                        ForEach(ReaderMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    Picker("Wide page handling", selection: Binding(
                        get: { model.state.readerPreferences.spreadBehavior },
                        set: model.setReaderSpreadBehavior
                    )) {
                        ForEach(ReaderSpreadBehavior.allCases) { behavior in
                            Text(behavior.title).tag(behavior)
                        }
                    }
                } header: {
                    Text("Reading Mode")
                } footer: {
                    Text("Wide page handling affects paged modes only.")
                }

                Section("Color Filter") {
                    Toggle("Enable color filter", isOn: Binding(
                        get: { model.state.readerPreferences.colorFilter.enabled },
                        set: model.setColorFilterEnabled
                    ))
                    Slider(value: Binding(
                        get: { model.state.readerPreferences.colorFilter.grayscale },
                        set: model.setColorFilterGrayscale
                    ), in: 0...1) {
                        Text("Grayscale")
                    }
                    Slider(value: Binding(
                        get: { model.state.readerPreferences.colorFilter.dimming },
                        set: model.setColorFilterDimming
                    ), in: 0...1) {
                        Text("Dimming")
                    }
                }
            }
            .navigationTitle("Reader Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

