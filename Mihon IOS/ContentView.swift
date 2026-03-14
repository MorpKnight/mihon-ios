//
//  ContentView.swift
//  Mihon IOS
//
//  Created by Giovan Christoffel Sihombing on 13/03/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        AppChromeView()
            .tint(model.chromeTint)
            .preferredColorScheme(model.preferredColorScheme)
    }
}
