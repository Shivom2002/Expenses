import ExpensesCore
import SwiftUI

/// A browser-based fallback for institutions that require an OAuth handoff,
/// such as Chase, when the app is signed with a free Apple Personal Team.
struct HostedPlaidLinkButton: View {
    private let api: ExpensesAPIClient
    private let onConnected: (@MainActor () async -> Void)?

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var isOpening = false
    @State private var isAwaitingBrowserCompletion = false
    @State private var didLeaveApp = false
    @State private var statusMessage: String?

    init(apiBaseURL: URL, onConnected: (@MainActor () async -> Void)? = nil) {
        self.api = ExpensesAPIClient(baseURL: apiBaseURL)
        self.onConnected = onConnected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Task { await openHostedLink() }
            } label: {
                Label("Connect Chase in browser", systemImage: "safari")
            }
            .disabled(isOpening)

            if isOpening {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Opening secure Plaid connection…")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard isAwaitingBrowserCompletion else { return }
            switch newPhase {
            case .inactive, .background:
                didLeaveApp = true
            case .active where didLeaveApp:
                didLeaveApp = false
                isAwaitingBrowserCompletion = false
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    await onConnected?()
                }
            default:
                break
            }
        }
    }

    @MainActor
    private func openHostedLink() async {
        isOpening = true
        statusMessage = nil
        defer { isOpening = false }

        do {
            let token = try await api.createLinkToken(presentation: .hosted)
            guard let hostedURL = token.hostedLinkURL else {
                statusMessage = "Plaid did not provide a browser connection link."
                return
            }
            isAwaitingBrowserCompletion = true
            statusMessage = "Finish Chase in your browser, then return to Expenses. Your account may take a moment to sync."
            openURL(hostedURL)
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
