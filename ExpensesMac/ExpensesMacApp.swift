import ExpensesCore
import SwiftUI

@main
struct ExpensesMacApp: App {
    private let environment = AppEnvironment.development

    var body: some Scene {
        WindowGroup {
            MacWelcomeView(apiBaseURL: environment.apiBaseURL)
        }
        .defaultSize(width: 1_080, height: 720)
    }
}
