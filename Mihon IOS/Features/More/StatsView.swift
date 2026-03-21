//
//  StatsView.swift
//  Mihon IOS
//

import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            if model.hasMeaningfulStats {
                ForEach(model.statsSections()) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                LabeledContent {
                                    Text(item.value)
                                        .font(.headline)
                                } label: {
                                    Label(item.title, systemImage: item.systemImage)
                                }

                                if let detail = item.detail {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Reading Stats Yet",
                    systemImage: "chart.bar",
                    description: Text("Start adding titles, reading chapters, and building progress to see your stats here.")
                )
            }
        }
        .navigationTitle("Stats")
    }
}
