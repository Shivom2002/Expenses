//
//  ContentView.swift
//  Expenses
//

import SwiftData
import SwiftUI
import ExpensesCore

struct ContentView: View {
    let apiBaseURL: URL

    @Query(sort: \ExpensesCore.Transaction.date, order: .reverse) private var transactions: [ExpensesCore.Transaction]

    var body: some View {
        NavigationStack {
            CashFlowDashboard(transactions: transactions, apiBaseURL: apiBaseURL)
                .navigationTitle("Cash Flow")
                .navigationBarTitleDisplayMode(.large)
        }
        .tint(Color.expensesGreen)
    }
}

#Preview {
    ContentView(apiBaseURL: AppEnvironment.development.apiBaseURL)
        .modelContainer(for: [Account.self, Transaction.self, Category.self, RecurringItem.self], inMemory: true)
}
