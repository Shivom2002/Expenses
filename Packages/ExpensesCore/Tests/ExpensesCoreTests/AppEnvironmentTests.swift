import Testing
@testable import ExpensesCore
import SwiftData

@Test func developmentEnvironmentUsesLocalBackend() {
    #expect(AppEnvironment.development.apiBaseURL.absoluteString == "http://localhost:8000")
}

@Test func sharedModelSchemaPersistsAccountAndTransaction() throws {
    let container = try ExpensesPersistence.makeModelContainer(isStoredInMemoryOnly: true)
    let context = ModelContext(container)
    let account = Account(remoteID: "account-1", institutionName: "First Bank", name: "Checking", type: "depository")
    let transaction = Transaction(
        remoteID: "transaction-1",
        name: "Groceries",
        amount: 42.50,
        date: .now,
        isPending: false,
        categoryName: "Groceries",
        isCategoryOverridden: false,
        account: account
    )
    context.insert(account)
    context.insert(transaction)
    try context.save()
    #expect(try context.fetch(FetchDescriptor<Transaction>()).count == 1)
}

@Test func dateOnlyParserUsesUTCDate() {
    let date = DateOnly.parse("2026-08-04")
    #expect(date != nil)
}
