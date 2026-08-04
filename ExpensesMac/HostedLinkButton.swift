import AppKit
import AuthenticationServices
import ExpensesCore
import SwiftUI

struct HostedLinkButton: View {
    @StateObject private var coordinator: HostedLinkCoordinator

    init(apiBaseURL: URL) {
        _coordinator = StateObject(wrappedValue: HostedLinkCoordinator(api: ExpensesAPIClient(baseURL: apiBaseURL)))
    }

    var body: some View {
        VStack(spacing: 8) {
            Button("Connect an account") {
                coordinator.start()
            }
            .buttonStyle(.borderedProminent)
            .disabled(coordinator.isWorking)

            if let statusMessage = coordinator.statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
private final class HostedLinkCoordinator: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var isWorking = false
    @Published var statusMessage: String?
    private let api: any ExpensesAPI
    private var webSession: ASWebAuthenticationSession?

    init(api: any ExpensesAPI) {
        self.api = api
    }

    func start() {
        isWorking = true
        statusMessage = nil
        Task {
            do {
                let token = try await api.createLinkToken(presentation: .hosted)
                guard let url = token.hostedLinkURL else {
                    throw APIClientError.invalidResponse
                }
                open(url)
            } catch {
                statusMessage = error.localizedDescription
                isWorking = false
            }
        }
    }

    private func open(_ url: URL) {
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "expenses"
        ) { [weak self] _, error in
            Task { @MainActor in
                self?.isWorking = false
                self?.statusMessage = error == nil
                    ? "Connection submitted. The backend will finish syncing once Plaid confirms it."
                    : "Account connection was cancelled."
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true
        webSession = session
        session.start()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
    }
}
