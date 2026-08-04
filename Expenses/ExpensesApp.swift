//
//  ExpensesApp.swift
//  Expenses
//
//  Created by Shivom Dhamija on 8/3/26.
//

import SwiftUI
import ExpensesCore

@main
struct ExpensesApp: App {
    private let environment = AppEnvironment.development

    var body: some Scene {
        WindowGroup {
            ContentView(apiBaseURL: environment.apiBaseURL)
        }
    }
}
