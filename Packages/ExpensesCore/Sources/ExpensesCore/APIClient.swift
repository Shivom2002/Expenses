import Foundation
import Security

public enum APIClientError: LocalizedError {
    case missingBearerToken
    case invalidResponse
    case server(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .missingBearerToken:
            "Connect the app to its backend before syncing."
        case .invalidResponse:
            "The backend returned an invalid response."
        case let .server(statusCode, message):
            "Backend error \(statusCode): \(message)"
        }
    }
}

public protocol BearerTokenProviding: Sendable {
    func bearerToken() throws -> String?
}

public struct KeychainBearerTokenProvider: BearerTokenProviding {
    public let service: String
    public let account: String

    public init(service: String = "com.shivomdhamija.Expenses", account: String = "backend-api-token") {
        self.service = service
        self.account = account
    }

    public func bearerToken() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            throw APIClientError.missingBearerToken
        }
        return token
    }

    public func save(_ token: String) throws {
        let value = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes = [kSecValueData as String: value]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = value
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else { throw APIClientError.missingBearerToken }
        } else if status != errSecSuccess {
            throw APIClientError.missingBearerToken
        }
    }

    public func remove() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIClientError.missingBearerToken
        }
    }
}

public protocol ExpensesAPI: Sendable {
    func createLinkToken(presentation: LinkPresentation) async throws -> RemoteLinkToken
    func exchangePublicToken(
        _ publicToken: String,
        institutionName: String,
        institutionID: String?
    ) async throws
    func accounts() async throws -> [RemoteAccount]
    func transactions() async throws -> [RemoteTransaction]
    func sync() async throws -> RemoteSyncResult
    func overrideCategory(transactionID: String, category: String) async throws -> RemoteTransaction
}

public actor ExpensesAPIClient: ExpensesAPI {
    private let baseURL: URL
    private let tokenProvider: any BearerTokenProviding
    private let session: URLSession

    public init(
        baseURL: URL,
        tokenProvider: any BearerTokenProviding = KeychainBearerTokenProvider(),
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
    }

    public func createLinkToken(presentation: LinkPresentation) async throws -> RemoteLinkToken {
        try await send(
            path: "plaid/link-token",
            method: "POST",
            body: LinkTokenRequest(presentation: presentation.rawValue)
        )
    }

    public func exchangePublicToken(
        _ publicToken: String,
        institutionName: String,
        institutionID: String?
    ) async throws {
        let _: EmptyResponse = try await send(
            path: "plaid/exchange-public-token",
            method: "POST",
            body: PublicTokenExchangeRequest(
                publicToken: publicToken,
                institutionName: institutionName,
                institutionID: institutionID
            )
        )
    }

    public func accounts() async throws -> [RemoteAccount] {
        try await send(path: "accounts", method: "GET")
    }

    public func transactions() async throws -> [RemoteTransaction] {
        try await send(path: "transactions", method: "GET")
    }

    public func sync() async throws -> RemoteSyncResult {
        try await send(path: "sync", method: "POST")
    }

    public func overrideCategory(transactionID: String, category: String) async throws -> RemoteTransaction {
        try await send(
            path: "transactions/\(transactionID)",
            method: "PATCH",
            body: CategoryOverrideRequest(category: category)
        )
    }

    private func send<Response: Decodable>(path: String, method: String) async throws -> Response {
        try await request(path: path, method: method, body: nil)
    }

    private func send<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body
    ) async throws -> Response {
        try await request(path: path, method: method, body: JSONEncoder().encode(body))
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        body: Data?
    ) async throws -> Response {
        guard let token = try tokenProvider.bearerToken(), !token.isEmpty else {
            throw APIClientError.missingBearerToken
        }
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Request failed"
            throw APIClientError.server(statusCode: httpResponse.statusCode, message: message)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw APIClientError.invalidResponse
        }
    }
}

private struct CategoryOverrideRequest: Encodable {
    let category: String
}

private struct LinkTokenRequest: Encodable {
    let presentation: String
}

private struct PublicTokenExchangeRequest: Encodable {
    let publicToken: String
    let institutionName: String
    let institutionID: String?

    enum CodingKeys: String, CodingKey {
        case publicToken = "public_token"
        case institutionName = "institution_name"
        case institutionID = "institution_id"
    }
}

private struct EmptyResponse: Decodable {}

public enum LinkPresentation: String, Sendable {
    case native
    case hosted
}

public struct RemoteLinkToken: Codable, Sendable {
    public let linkToken: String
    public let expiration: String
    public let hostedLinkURL: URL?

    enum CodingKeys: String, CodingKey {
        case linkToken = "link_token"
        case expiration
        case hostedLinkURL = "hosted_link_url"
    }
}

public struct RemoteAccount: Codable, Sendable, Identifiable {
    public let id: String
    public let institutionName: String
    public let name: String
    public let officialName: String?
    public let type: String
    public let subtype: String?
    public let mask: String?
    public let currentBalance: Double?
    public let availableBalance: Double?
    public let currency: String?

    enum CodingKeys: String, CodingKey {
        case id
        case institutionName = "institution_name"
        case name
        case officialName = "official_name"
        case type
        case subtype
        case mask
        case currentBalance = "current_balance"
        case availableBalance = "available_balance"
        case currency
    }
}

public struct RemoteTransaction: Codable, Sendable, Identifiable {
    public let id: String
    public let accountID: String
    public let accountName: String
    public let merchantName: String?
    public let merchantLogoURL: String?
    public let name: String
    public let amount: Double
    public let date: String
    public let pending: Bool
    public let category: String
    public let categoryOverridden: Bool
    public let currency: String?

    enum CodingKeys: String, CodingKey {
        case id
        case accountID = "account_id"
        case accountName = "account_name"
        case merchantName = "merchant_name"
        case merchantLogoURL = "merchant_logo_url"
        case name
        case amount
        case date
        case pending
        case category
        case categoryOverridden = "category_overridden"
        case currency
    }
}

public struct RemoteSyncResult: Codable, Sendable {
    public let syncedItems: Int
    public let upsertedTransactions: Int
    public let removedTransactions: Int

    enum CodingKeys: String, CodingKey {
        case syncedItems = "synced_items"
        case upsertedTransactions = "upserted_transactions"
        case removedTransactions = "removed_transactions"
    }
}
