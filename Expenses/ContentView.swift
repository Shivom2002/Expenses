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
            VStack(spacing: 16) {
                Text("Expenses is ready for its secure backend connection at \(apiBaseURL.host ?? "localhost").")
                PlaidLinkButton(apiBaseURL: apiBaseURL)
            }
        }
    }
}

#Preview {
    ContentView(apiBaseURL: AppEnvironment.development.apiBaseURL)
}
