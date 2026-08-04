import Foundation

/// Configuration shared by the native iOS and macOS clients.
///
/// The API base URL is deliberately not a secret. Credentials and Plaid access
/// tokens stay on the backend or in the platform Keychain, respectively.
public struct AppEnvironment: Sendable, Equatable {
    public let apiBaseURL: URL

    public init(apiBaseURL: URL) {
        self.apiBaseURL = apiBaseURL
    }

    public static let development = AppEnvironment(
        apiBaseURL: URL(string: "http://localhost:8000")!
    )
}
