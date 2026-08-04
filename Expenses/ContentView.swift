//
//  ContentView.swift
//  Expenses
//
//  Created by Shivom Dhamija on 8/3/26.
//

import SwiftUI
import ExpensesCore

struct ContentView: View {
    let apiBaseURL: URL

    var body: some View {
        ContentUnavailableView {
            Label("Your financial picture, in one place", systemImage: "chart.line.uptrend.xyaxis")
        } description: {
            Text("Expenses is ready for its secure backend connection at \(apiBaseURL.host ?? "localhost").")
        }
    }
}

#Preview {
    ContentView(apiBaseURL: AppEnvironment.development.apiBaseURL)
}
