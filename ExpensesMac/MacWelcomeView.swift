import SwiftUI
import ExpensesCore

struct MacWelcomeView: View {
    let apiBaseURL: URL

    var body: some View {
        ContentUnavailableView {
            Label("Your financial picture, in one place", systemImage: "chart.line.uptrend.xyaxis")
        } description: {
            VStack(spacing: 16) {
                Text("Expenses is ready for its secure backend connection.")
                HostedLinkButton(apiBaseURL: apiBaseURL)
            }
        }
    }
}

#Preview {
    MacWelcomeView(apiBaseURL: AppEnvironment.development.apiBaseURL)
}
