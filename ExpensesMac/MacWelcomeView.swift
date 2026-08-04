import SwiftUI
import ExpensesCore

struct MacWelcomeView: View {
    let apiBaseURL: URL

    var body: some View {
        ContentUnavailableView {
            Label("Your financial picture, in one place", systemImage: "chart.line.uptrend.xyaxis")
        } description: {
            Text("Expenses is ready for its secure backend connection.")
        }
    }
}

#Preview {
    MacWelcomeView(apiBaseURL: AppEnvironment.development.apiBaseURL)
}
