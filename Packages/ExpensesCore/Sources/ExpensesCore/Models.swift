import Foundation
import SwiftData

@Model
public final class Account {
    @Attribute(.unique) public var remoteID: String
    public var institutionName: String
    public var name: String
    public var officialName: String?
    public var type: String
    public var subtype: String?
    public var mask: String?
    public var currentBalance: Double?
    public var availableBalance: Double?
    public var currencyCode: String?
    public var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Transaction.account) public var transactions: [Transaction] = []

    public init(
        remoteID: String,
        institutionName: String,
        name: String,
        officialName: String? = nil,
        type: String,
        subtype: String? = nil,
        mask: String? = nil,
        currentBalance: Double? = nil,
        availableBalance: Double? = nil,
        currencyCode: String? = nil,
        updatedAt: Date = .now
    ) {
        self.remoteID = remoteID
        self.institutionName = institutionName
        self.name = name
        self.officialName = officialName
        self.type = type
        self.subtype = subtype
        self.mask = mask
        self.currentBalance = currentBalance
        self.availableBalance = availableBalance
        self.currencyCode = currencyCode
        self.updatedAt = updatedAt
    }
}

@Model
public final class Transaction {
    @Attribute(.unique) public var remoteID: String
    public var merchantName: String?
    public var merchantLogoURL: String?
    public var name: String
    /// Plaid convention: positive is money out; negative is money in.
    public var amount: Double
    public var date: Date
    public var isPending: Bool
    public var categoryName: String
    public var isCategoryOverridden: Bool
    public var splitFraction: Double
    public var customShareAmount: Double?
    public var currencyCode: String?
    public var account: Account?

    public init(
        remoteID: String,
        merchantName: String? = nil,
        merchantLogoURL: String? = nil,
        name: String,
        amount: Double,
        date: Date,
        isPending: Bool,
        categoryName: String,
        isCategoryOverridden: Bool,
        splitFraction: Double = 1,
        customShareAmount: Double? = nil,
        currencyCode: String? = nil,
        account: Account? = nil
    ) {
        self.remoteID = remoteID
        self.merchantName = merchantName
        self.merchantLogoURL = merchantLogoURL
        self.name = name
        self.amount = amount
        self.date = date
        self.isPending = isPending
        self.categoryName = categoryName
        self.isCategoryOverridden = isCategoryOverridden
        self.splitFraction = splitFraction
        self.customShareAmount = customShareAmount
        self.currencyCode = currencyCode
        self.account = account
    }
}

public extension Transaction {
    /// Internal transfers and credit card payments move money between accounts and should not be counted twice.
    var countsTowardCashFlow: Bool {
        !["Card Payment", "Transfers"].contains(categoryName)
    }

    var effectiveAmount: Double {
        if let customShareAmount {
            return customShareAmount * (amount < 0 ? -1 : 1)
        }
        return amount * splitFraction
    }

    var hasSplit: Bool {
        customShareAmount != nil || splitFraction != 1
    }
}

@Model
public final class Category {
    @Attribute(.unique) public var slug: String
    public var name: String
    public var symbolName: String
    public var tintHex: String
    public var isIncome: Bool

    public init(slug: String, name: String, symbolName: String, tintHex: String, isIncome: Bool = false) {
        self.slug = slug
        self.name = name
        self.symbolName = symbolName
        self.tintHex = tintHex
        self.isIncome = isIncome
    }
}

@Model
public final class RecurringItem {
    @Attribute(.unique) public var remoteID: String
    public var merchantName: String
    public var merchantLogoURL: String?
    public var amount: Double
    public var currencyCode: String?
    public var cadence: String
    public var nextDueDate: Date
    public var isComplete: Bool

    public init(
        remoteID: String,
        merchantName: String,
        merchantLogoURL: String? = nil,
        amount: Double,
        currencyCode: String? = nil,
        cadence: String,
        nextDueDate: Date,
        isComplete: Bool = false
    ) {
        self.remoteID = remoteID
        self.merchantName = merchantName
        self.merchantLogoURL = merchantLogoURL
        self.amount = amount
        self.currencyCode = currencyCode
        self.cadence = cadence
        self.nextDueDate = nextDueDate
        self.isComplete = isComplete
    }
}

public enum ExpensesPersistence {
    public static func makeModelContainer(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        let schema = Schema([Account.self, Transaction.self, Category.self, RecurringItem.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isStoredInMemoryOnly)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
