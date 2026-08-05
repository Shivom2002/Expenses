import LinkKit
import SwiftUI
import ExpensesCore

struct PlaidLinkButton: View {
    private let api: ExpensesAPIClient
    private let onConnected: (@MainActor () async -> Void)?
    @State private var linkSession: PlaidLinkSession?
    @State private var isPresentingLink = false
    @State private var isReady = false
    @State private var statusMessage: String?

    init(apiBaseURL: URL, onConnected: (@MainActor () async -> Void)? = nil) {
        self.api = ExpensesAPIClient(baseURL: apiBaseURL)
        self.onConnected = onConnected
    }

    var body: some View {
        VStack(spacing: 8) {
            Button {
                isPresentingLink = true
            } label: {
                Label("Connect an account", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isReady)
            .task { await prepareLink() }
            .sheet(isPresented: $isPresentingLink) {
                if let linkSession {
                    linkSession.sheet()
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @MainActor
    private func prepareLink() async {
        do {
            let token = try await api.createLinkToken(presentation: .native)
            let configuration = LinkTokenConfiguration(
                token: token.linkToken,
                onSuccess: { success in
                    let publicToken = success.publicToken
                    let institution = success.metadata.institution
                    Task { @MainActor in
                        do {
                            try await api.exchangePublicToken(
                                publicToken,
                                institutionName: institution.name,
                                institutionID: institution.id
                            )
                            await onConnected?()
                            statusMessage = "Account connected and your transactions are synced."
                        } catch {
                            statusMessage = error.localizedDescription
                        }
                        isPresentingLink = false
                    }
                },
                onExit: { _ in
                    Task { @MainActor in isPresentingLink = false }
                },
                onEvent: nil,
                onLoad: {
                    Task { @MainActor in isReady = true }
                }
            )
            linkSession = try Plaid.createPlaidLinkSession(configuration: configuration)
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
