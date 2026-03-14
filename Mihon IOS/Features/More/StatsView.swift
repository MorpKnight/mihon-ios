//
//  StatsView.swift
//  Mihon IOS
//

import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            ForEach(model.statsSummary()) { item in
                LabeledContent {
                    Text(item.value)
                        .font(.headline)
                } label: {
                    Label(item.title, systemImage: item.systemImage)
                }
            }
        }
        .navigationTitle("Stats")
    }
}
