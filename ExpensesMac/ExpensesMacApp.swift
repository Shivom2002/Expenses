import ExpensesCore
import SwiftUI
import SwiftData

@main
struct ExpensesMacApp: App {
    private let environment = AppEnvironment.development
    private let modelContainer = try! ExpensesPersistence.makeModelContainer()

    var body: some Scene {
        WindowGroup {
            MacWelcomeView(apiBaseURL: environment.apiBaseURL)
        }
        .defaultSize(width: 1_080, height: 720)
        .modelContainer(modelContainer)
    }
}
