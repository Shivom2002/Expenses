//
//  ExpensesApp.swift
//  Expenses
//
//  Created by Shivom Dhamija on 8/3/26.
//

import SwiftUI
import ExpensesCore
import SwiftData

@main
struct ExpensesApp: App {
    private let environment = AppEnvironment.development
    private let modelContainer = try! ExpensesPersistence.makeModelContainer()

    var body: some Scene {
        WindowGroup {
            ContentView(apiBaseURL: environment.apiBaseURL)
        }
        .modelContainer(modelContainer)
    }
}
