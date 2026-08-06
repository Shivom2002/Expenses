//
//  BackendSetupView.swift
//  Expenses
//

import SwiftUI
import SwiftData
import ExpensesCore

struct BackendSetupView: View {
    @Binding var baseURLString: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var draftBaseURL: String
    @State private var bearerToken = ""
    @State private var status: ConnectionStatus = .idle
    @State private var isShowingClearConfirmation = false
    @State private var isRefreshingAccounts = false
    @State private var accountRefreshMessage: String?
    @State private var accountRefreshFailed = false

    private let tokenProvider = KeychainBearerTokenProvider()

    init(baseURLString: Binding<String>) {
        _baseURLString = baseURLString
        _draftBaseURL = State(initialValue: baseURLString.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Secure backend") {
                    TextField("https://your-app.fly.dev", text: $draftBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    Text("Use the HTTPS address Fly.io gives your deployed API. Your iPhone cannot use your Mac’s localhost address.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("App access token") {
                    SecureField("Bearer token", text: $bearerToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Text("This is your API_BEARER_TOKEN from the backend, not a Plaid secret. It is stored only in this device’s Keychain.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Bank accounts") {
                    if let apiBaseURL = normalizedURL,
                       !bearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        PlaidLinkButton(apiBaseURL: apiBaseURL) {
                            await refreshAccounts()
                        }

                        Button("Refresh accounts") {
                            Task { await refreshAccounts() }
                        }
                        .disabled(isRefreshingAccounts)

                        if isRefreshingAccounts {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Refreshing accounts and transactions…")
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        } else if let accountRefreshMessage {
                            Label(
                                accountRefreshMessage,
                                systemImage: accountRefreshFailed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                            )
                            .font(.footnote)
                            .foregroundStyle(accountRefreshFailed ? .red : Color.expensesGreen)
                        }
                    } else {
                        Text("Save your backend connection and app access token before linking an account.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Text("Add another checking, savings, credit-card, or bank account through Plaid Link.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Save connection") {
                        saveConnection()
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasValidURL || bearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Test connection") {
                        Task { await testConnection() }
                    }
                    .disabled(!hasValidURL)

                    if case let .success(message) = status {
                        Label(message, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.expensesGreen)
                    } else if case let .failure(message) = status {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    } else if status == .testing {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Checking backend…")
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Remove saved token", role: .destructive) {
                        do {
                            try tokenProvider.remove()
                            bearerToken = ""
                            status = .idle
                        } catch {
                            status = .failure("Could not remove the saved token.")
                        }
                    }
                } footer: {
                    Text("Plaid client IDs, secrets, and access tokens never belong in the app.")
                }

                Section("Data") {
                    Button("Clear all synced data", role: .destructive) {
                        isShowingClearConfirmation = true
                    }
                    .disabled(!hasValidURL)

                    Text("Use this once when moving from Plaid Sandbox to Production. It removes the saved test accounts and transactions from this backend and iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Backend setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                bearerToken = (try? tokenProvider.bearerToken()) ?? ""
            }
            .confirmationDialog(
                "Clear all synced data?",
                isPresented: $isShowingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear test data", role: .destructive) {
                    Task { await clearSyncedData() }
                }
            } message: {
                Text("This permanently deletes the connected Sandbox accounts and transactions from the backend and this iPhone. It does not change your actual bank account.")
            }
        }
    }

    private var normalizedURL: URL? {
        let text = draftBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), let host = url.host else { return nil }
        guard url.scheme == "https" || (url.scheme == "http" && host == "localhost") else { return nil }
        return url
    }

    private var hasValidURL: Bool {
        normalizedURL != nil
    }

    private func saveConnection() {
        guard let url = normalizedURL else {
            status = .failure("Enter a valid HTTPS backend address.")
            return
        }
        do {
            try tokenProvider.save(bearerToken.trimmingCharacters(in: .whitespacesAndNewlines))
            baseURLString = url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            status = .success("Connection saved securely on this iPhone.")
        } catch {
            status = .failure("Could not save the token to Keychain.")
        }
    }

    @MainActor
    private func refreshAccounts() async {
        guard let apiBaseURL = normalizedURL else { return }
        isRefreshingAccounts = true
        accountRefreshMessage = nil
        defer { isRefreshingAccounts = false }

        let store = FinanceDataStore(api: ExpensesAPIClient(baseURL: apiBaseURL))
        await store.refresh(modelContext: modelContext)
        if let error = store.lastError {
            accountRefreshFailed = true
            accountRefreshMessage = "Could not refresh accounts: \(error)"
        } else {
            accountRefreshFailed = false
            accountRefreshMessage = "Accounts and transactions refreshed."
        }
    }

    @MainActor
    private func clearSyncedData() async {
        guard let baseURL = normalizedURL else {
            status = .failure("Enter a valid HTTPS backend address.")
            return
        }
        status = .testing
        do {
            let store = FinanceDataStore(api: ExpensesAPIClient(baseURL: baseURL))
            try await store.clearSyncedData(modelContext: modelContext)
            status = .success("Sandbox accounts and transactions cleared.")
        } catch {
            status = .failure("Could not clear synced data. Try again while the backend is online.")
        }
    }

    @MainActor
    private func testConnection() async {
        guard let baseURL = normalizedURL else {
            status = .failure("Enter a valid HTTPS backend address.")
            return
        }
        status = .testing
        do {
            let healthURL = baseURL.appending(path: "health")
            let (_, response) = try await URLSession.shared.data(from: healthURL)
            guard let response = response as? HTTPURLResponse, (200 ..< 300).contains(response.statusCode) else {
                status = .failure("The backend did not return a successful health check.")
                return
            }
            status = .success("Backend is reachable.")
        } catch {
            status = .failure("Could not reach this backend. Check its URL and deployment status.")
        }
    }
}

private enum ConnectionStatus: Equatable {
    case idle
    case testing
    case success(String)
    case failure(String)
}
