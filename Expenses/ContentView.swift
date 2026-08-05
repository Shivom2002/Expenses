//
//  ContentView.swift
//  Expenses
//

import SwiftData
import SwiftUI
import ExpensesCore

struct ContentView: View {
    private let defaultAPIBaseURL: URL
    @AppStorage("backendBaseURL") private var backendBaseURL = ""
    @State private var isShowingBackendSetup = false

    @Query(sort: \ExpensesCore.Transaction.date, order: .reverse) private var transactions: [ExpensesCore.Transaction]

    init(apiBaseURL: URL) {
        defaultAPIBaseURL = apiBaseURL
        _backendBaseURL = AppStorage(wrappedValue: apiBaseURL.absoluteString, "backendBaseURL")
    }

    private var apiBaseURL: URL {
        URL(string: backendBaseURL) ?? defaultAPIBaseURL
    }

    var body: some View {
        NavigationStack {
            CashFlowDashboard(transactions: transactions, apiBaseURL: apiBaseURL)
                .navigationTitle("Cash Flow")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Backend setup", systemImage: "gearshape") {
                            isShowingBackendSetup = true
                        }
                        .accessibilityLabel("Backend setup")
                    }
                }
        }
        .tint(Color.expensesGreen)
        .sheet(isPresented: $isShowingBackendSetup) {
            BackendSetupView(baseURLString: $backendBaseURL)
        }
    }
}

#Preview {
    ContentView(apiBaseURL: AppEnvironment.development.apiBaseURL)
        .modelContainer(for: [Account.self, Transaction.self, Category.self, RecurringItem.self], inMemory: true)
}
