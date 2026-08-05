//
//  TransactionListView.swift
//  Expenses
//

import SwiftUI
import ExpensesCore

enum TransactionFilter: Hashable {
    case all
    case income
    case expenses
    case savings
    case category(String)

    var title: String {
        switch self {
        case .all: "Transactions"
        case .income: "Income"
        case .expenses: "Expenses"
        case .savings: "Savings"
        case let .category(name): name
        }
    }

    var summary: String {
        switch self {
        case .all: "Every transaction across your connected accounts."
        case .income: "Money received across your connected accounts."
        case .expenses: "Money spent across your connected accounts."
        case .savings: "Money in and out that determines your net savings."
        case let .category(name): "Every transaction categorized as \(name)."
        }
    }

    func matches(_ transaction: ExpensesCore.Transaction) -> Bool {
        switch self {
        case .all, .savings:
            true
        case .income:
            transaction.amount < 0
        case .expenses:
            transaction.amount > 0
        case let .category(name):
            transaction.categoryName == name
        }
    }
}

struct TransactionListView: View {
    let transactions: [ExpensesCore.Transaction]

    @State private var selectedFilter: TransactionFilter
    @State private var searchText = ""

    init(transactions: [ExpensesCore.Transaction], initialFilter: TransactionFilter = .all) {
        self.transactions = transactions
        _selectedFilter = State(initialValue: initialFilter)
    }

    private var filteredTransactions: [ExpensesCore.Transaction] {
        transactions
            .filter(selectedFilter.matches)
            .filter { transaction in
                guard !searchText.isEmpty else { return true }
                return transaction.name.localizedCaseInsensitiveContains(searchText)
                    || transaction.merchantName?.localizedCaseInsensitiveContains(searchText) == true
                    || transaction.categoryName.localizedCaseInsensitiveContains(searchText)
                    || transaction.account?.name.localizedCaseInsensitiveContains(searchText) == true
            }
            .sorted { $0.date > $1.date }
    }

    private var dateSections: [TransactionDateSection] {
        let grouped = Dictionary(grouping: filteredTransactions) { transaction in
            Calendar.current.startOfDay(for: transaction.date)
        }
        return grouped.map { date, transactions in
            TransactionDateSection(date: date, transactions: transactions.sorted { $0.date > $1.date })
        }
        .sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedFilter.title)
                        .font(.title3.bold())
                    Text(selectedFilter.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
            }

            if dateSections.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(dateSections) { section in
                    Section(section.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) {
                        ForEach(section.transactions, id: \.remoteID) { transaction in
                            NavigationLink {
                                TransactionDetailView(transaction: transaction)
                            } label: {
                                TransactionRow(transaction: transaction)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(selectedFilter.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search transactions")
        .safeAreaInset(edge: .top, spacing: 0) {
            filterPicker
        }
    }

    private var filterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(primaryFilters, id: \.self) { filter in
                    Button(filter.title) {
                        selectedFilter = filter
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selectedFilter == filter ? Color.white : Color.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(selectedFilter == filter ? Color.expensesGreen : Color(.secondarySystemBackground), in: Capsule())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    private var primaryFilters: [TransactionFilter] {
        [.all, .income, .expenses, .savings]
    }
}

private struct TransactionDateSection: Identifiable {
    let date: Date
    let transactions: [ExpensesCore.Transaction]

    var id: Date { date }
}

private struct TransactionRow: View {
    let transaction: ExpensesCore.Transaction

    private var merchant: String {
        transaction.merchantName?.isEmpty == false ? transaction.merchantName! : transaction.name
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(String(merchant.prefix(1)).uppercased())
                .font(.subheadline.weight(.bold))
                .foregroundStyle(transaction.amount < 0 ? Color.expensesGreen : Color.primary)
                .frame(width: 40, height: 40)
                .background(transaction.amount < 0 ? Color.expensesGreen.opacity(0.14) : Color.secondary.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(merchant)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(transaction.isPending ? "Pending" : transaction.categoryName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(displayAmount)
                .font(.body.weight(.semibold))
                .foregroundStyle(transaction.amount < 0 ? Color.expensesGreen : Color.primary)
        }
        .padding(.vertical, 4)
    }

    private var displayAmount: String {
        let sign = transaction.amount < 0 ? "+" : "−"
        return sign + transaction.amount.magnitude.formatted(.currency(code: transaction.currencyCode ?? "USD"))
    }
}

private struct TransactionDetailView: View {
    let transaction: ExpensesCore.Transaction

    private var merchant: String {
        transaction.merchantName?.isEmpty == false ? transaction.merchantName! : transaction.name
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Text(String(merchant.prefix(1)).uppercased())
                        .font(.title.bold())
                        .foregroundStyle(transaction.amount < 0 ? Color.expensesGreen : Color.primary)
                        .frame(width: 62, height: 62)
                        .background(transaction.amount < 0 ? Color.expensesGreen.opacity(0.14) : Color.secondary.opacity(0.12), in: Circle())
                    Text(merchant)
                        .font(.title3.bold())
                    Text(displayAmount)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(transaction.amount < 0 ? Color.expensesGreen : Color.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .listRowBackground(Color.clear)
            }

            Section("Details") {
                LabeledContent("Date", value: transaction.date.formatted(date: .long, time: .omitted))
                LabeledContent("Category", value: transaction.categoryName)
                if let accountName = transaction.account?.name {
                    LabeledContent("Account", value: accountName)
                }
                if transaction.isPending {
                    LabeledContent("Status", value: "Pending")
                }
            }
        }
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var displayAmount: String {
        let sign = transaction.amount < 0 ? "+" : "−"
        return sign + transaction.amount.magnitude.formatted(.currency(code: transaction.currencyCode ?? "USD"))
    }
}
