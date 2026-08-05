//
//  BackendSetupView.swift
//  Expenses
//

import SwiftUI
import ExpensesCore

struct BackendSetupView: View {
    @Binding var baseURLString: String

    @Environment(\.dismiss) private var dismiss
    @State private var draftBaseURL: String
    @State private var bearerToken = ""
    @State private var status: ConnectionStatus = .idle

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
