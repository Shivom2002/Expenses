import Foundation
import Observation
import SwiftData

@MainActor
@Observable
public final class FinanceDataStore {
    public private(set) var isRefreshing = false
    public private(set) var lastSync: RemoteSyncResult?
    public private(set) var lastError: String?
    private let api: any ExpensesAPI

    public init(api: any ExpensesAPI) {
        self.api = api
    }

    public func refresh(modelContext: ModelContext) async {
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        do {
            try await api.recategorizeTransactions()
            lastSync = try await api.sync()
            async let remoteAccounts = api.accounts()
            async let remoteTransactions = api.transactions()
            let (accounts, transactions) = try await (remoteAccounts, remoteTransactions)
            try apply(accounts: accounts, transactions: transactions, to: modelContext)
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func clearSyncedData(modelContext: ModelContext) async throws {
        try await api.clearData()

        let transactions = try modelContext.fetch(FetchDescriptor<Transaction>())
        for transaction in transactions {
            modelContext.delete(transaction)
        }
        let accounts = try modelContext.fetch(FetchDescriptor<Account>())
        for account in accounts {
            modelContext.delete(account)
        }
        try modelContext.save()
    }

    public func apply(
        accounts remoteAccounts: [RemoteAccount],
        transactions remoteTransactions: [RemoteTransaction],
        to modelContext: ModelContext
    ) throws {
        let localAccounts = try modelContext.fetch(FetchDescriptor<Account>())
        var accountsByRemoteID = Dictionary(uniqueKeysWithValues: localAccounts.map { ($0.remoteID, $0) })

        for remote in remoteAccounts {
            let account = accountsByRemoteID[remote.id] ?? Account(
                remoteID: remote.id,
                institutionName: remote.institutionName,
                name: remote.name,
                type: remote.type
            )
            account.institutionName = remote.institutionName
            account.name = remote.name
            account.officialName = remote.officialName
            account.type = remote.type
            account.subtype = remote.subtype
            account.mask = remote.mask
            account.currentBalance = remote.currentBalance
            account.availableBalance = remote.availableBalance
            account.currencyCode = remote.currency
            account.updatedAt = .now
            if accountsByRemoteID[remote.id] == nil {
                modelContext.insert(account)
                accountsByRemoteID[remote.id] = account
            }
        }

        let localTransactions = try modelContext.fetch(FetchDescriptor<Transaction>())
        let transactionsByRemoteID = Dictionary(uniqueKeysWithValues: localTransactions.map { ($0.remoteID, $0) })
        for remote in remoteTransactions {
            guard let date = DateOnly.parse(remote.date) else { continue }
            let transaction = transactionsByRemoteID[remote.id] ?? Transaction(
                remoteID: remote.id,
                name: remote.name,
                amount: remote.amount,
                date: date,
                isPending: remote.pending,
                categoryName: remote.category,
                isCategoryOverridden: remote.categoryOverridden,
                splitFraction: remote.splitFraction,
                customShareAmount: remote.customShareAmount
            )
            transaction.merchantName = remote.merchantName
            transaction.merchantLogoURL = remote.merchantLogoURL
            transaction.name = remote.name
            transaction.amount = remote.amount
            transaction.date = date
            transaction.isPending = remote.pending
            transaction.categoryName = remote.category
            transaction.isCategoryOverridden = remote.categoryOverridden
            transaction.splitFraction = remote.splitFraction
            transaction.customShareAmount = remote.customShareAmount
            transaction.currencyCode = remote.currency
            transaction.account = accountsByRemoteID[remote.accountID]
            if transactionsByRemoteID[remote.id] == nil {
                modelContext.insert(transaction)
            }
        }
        try modelContext.save()
    }
}

public enum DateOnly {
    public static func parse(_ value: String) -> Date? {
        let pieces = value.split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3 else { return nil }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = pieces[0]
        components.month = pieces[1]
        components.day = pieces[2]
        return components.date
    }
}
