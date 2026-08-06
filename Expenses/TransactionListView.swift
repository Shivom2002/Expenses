//
//  TransactionListView.swift
//  Expenses
//

import SwiftUI
import SwiftData
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

    func summary(month: Date? = nil) -> String {
        let period = month.map { $0.formatted(.dateTime.month(.wide).year()) }
        return switch self {
        case .all: period.map { "Every transaction in \($0)." } ?? "Every transaction across your connected accounts."
        case .income: period.map { "Money received in \($0)." } ?? "Money received across your connected accounts."
        case .expenses: period.map { "Money spent in \($0)." } ?? "Money spent across your connected accounts."
        case .savings: period.map { "Money in and out that determines net savings in \($0)." } ?? "Money in and out that determines your net savings."
        case let .category(name): period.map { "Transactions categorized as \(name) in \($0)." } ?? "Every transaction categorized as \(name)."
        }
    }

    func matches(_ transaction: ExpensesCore.Transaction) -> Bool {
        switch self {
        case .all, .savings:
            self == .all || transaction.countsTowardCashFlow
        case .income:
            transaction.amount < 0
        case .expenses:
            transaction.amount > 0 && transaction.countsTowardCashFlow
        case let .category(name):
            transaction.categoryName == name
        }
    }
}

struct TransactionListView: View {
    let transactions: [ExpensesCore.Transaction]
    let month: Date?

    @State private var selectedFilter: TransactionFilter
    @State private var searchText = ""

    init(transactions: [ExpensesCore.Transaction], initialFilter: TransactionFilter = .all, month: Date? = nil) {
        self.transactions = transactions
        self.month = month
        _selectedFilter = State(initialValue: initialFilter)
    }

    private var filteredTransactions: [ExpensesCore.Transaction] {
        transactions
            .filter(selectedFilter.matches)
            .filter { transaction in
                guard let month else { return true }
                return Calendar.current.isDate(transaction.date, equalTo: month, toGranularity: .month)
            }
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
                    Text(selectedFilter.summary(month: month))
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

    @Environment(\.modelContext) private var modelContext
    @AppStorage("backendBaseURL") private var backendBaseURL = ""
    @State private var isShowingCategoryPicker = false
    @State private var isUpdatingCategory = false
    @State private var categoryError: String?
    @State private var isShowingSplitPicker = false
    @State private var isShowingCustomShare = false
    @State private var customShareText = ""
    @State private var isUpdatingSplit = false
    @State private var splitError: String?

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
                Button {
                    isShowingCategoryPicker = true
                } label: {
                    LabeledContent("Category") {
                        HStack(spacing: 6) {
                            Text(transaction.categoryName)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .disabled(isUpdatingCategory)
                if transaction.isCategoryOverridden {
                    Text("Manually set")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button {
                    isShowingSplitPicker = true
                } label: {
                    LabeledContent("Split") {
                        HStack(spacing: 6) {
                            Text(splitDescription)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .disabled(isUpdatingSplit)
                if transaction.hasSplit {
                    LabeledContent("Your share", value: displayEffectiveAmount)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let accountName = transaction.account?.name {
                    LabeledContent("Account", value: accountName)
                }
                if transaction.isPending {
                    LabeledContent("Status", value: "Pending")
                }
            }

            if let categoryError {
                Section {
                    Label(categoryError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            if let splitError {
                Section {
                    Label(splitError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingCategoryPicker) {
            NavigationStack {
                List {
                    Section("Choose a category") {
                        ForEach(TransactionCategoryOption.allCases) { category in
                            Button {
                                Task { await updateCategory(category.rawValue) }
                            } label: {
                                HStack {
                                    Text(category.rawValue)
                                    Spacer()
                                    if transaction.categoryName == category.rawValue {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.expensesGreen)
                                    }
                                }
                            }
                            .disabled(isUpdatingCategory)
                        }
                    }

                    if transaction.isCategoryOverridden {
                        Section {
                            Button("Use Plaid’s category", role: .destructive) {
                                Task { await updateCategory(nil) }
                            }
                            .disabled(isUpdatingCategory)
                        } footer: {
                            Text("This restores the category supplied by Plaid.")
                        }
                    }
                }
                .navigationTitle("Category")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isShowingCategoryPicker = false }
                    }
                }
                .overlay {
                    if isUpdatingCategory {
                        ProgressView("Saving category…")
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingSplitPicker) {
            NavigationStack {
                List {
                    Section("How much was your share?") {
                        SplitOptionButton(title: "Full amount", subtitle: "Count the entire transaction") {
                            Task { await updateSplit(fraction: 1) }
                        }
                        SplitOptionButton(title: "Half", subtitle: "Count ½ of the transaction") {
                            Task { await updateSplit(fraction: 0.5) }
                        }
                        SplitOptionButton(title: "Quarter", subtitle: "Count ¼ of the transaction") {
                            Task { await updateSplit(fraction: 0.25) }
                        }
                        Button("Custom amount…") {
                            isShowingSplitPicker = false
                            isShowingCustomShare = true
                        }
                    }
                }
                .navigationTitle("Split transaction")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isShowingSplitPicker = false }
                    }
                }
                .overlay {
                    if isUpdatingSplit {
                        ProgressView("Saving split…")
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
        }
        .alert("Custom share", isPresented: $isShowingCustomShare) {
            TextField("Amount", text: $customShareText)
                .keyboardType(.decimalPad)
            Button("Save") {
                guard let amount = Double(customShareText), amount > 0 else {
                    splitError = "Enter a valid amount for your share."
                    return
                }
                Task { await updateSplit(customAmount: amount) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter your portion of the \(transaction.amount.magnitude.formatted(.currency(code: transaction.currencyCode ?? "USD"))) transaction.")
        }
    }

    private var displayAmount: String {
        let sign = transaction.amount < 0 ? "+" : "−"
        return sign + transaction.amount.magnitude.formatted(.currency(code: transaction.currencyCode ?? "USD"))
    }

    private var displayEffectiveAmount: String {
        let sign = transaction.effectiveAmount < 0 ? "+" : "−"
        return sign + transaction.effectiveAmount.magnitude.formatted(.currency(code: transaction.currencyCode ?? "USD"))
    }

    private var splitDescription: String {
        if let customAmount = transaction.customShareAmount {
            return "Custom: \(customAmount.formatted(.currency(code: transaction.currencyCode ?? "USD")))"
        }
        return switch transaction.splitFraction {
        case 1: "Full amount"
        case 0.5: "½ share"
        case 0.25: "¼ share"
        default: "\(transaction.splitFraction.formatted(.percent.precision(.fractionLength(0)))) share"
        }
    }

    @MainActor
    private func updateCategory(_ category: String?) async {
        guard let apiBaseURL = URL(string: backendBaseURL) else {
            categoryError = "Set up the backend before changing categories."
            return
        }

        isUpdatingCategory = true
        categoryError = nil
        defer { isUpdatingCategory = false }
        do {
            let api = ExpensesAPIClient(baseURL: apiBaseURL)
            let remote = if let category {
                try await api.overrideCategory(transactionID: transaction.remoteID, category: category)
            } else {
                try await api.clearCategoryOverride(transactionID: transaction.remoteID)
            }
            transaction.categoryName = remote.category
            transaction.isCategoryOverridden = remote.categoryOverridden
            try modelContext.save()
            isShowingCategoryPicker = false
        } catch {
            categoryError = "Could not save this category. Check your backend connection and try again."
        }
    }

    @MainActor
    private func updateSplit(fraction: Double? = nil, customAmount: Double? = nil) async {
        guard let apiBaseURL = URL(string: backendBaseURL) else {
            splitError = "Set up the backend before saving a split."
            return
        }

        isUpdatingSplit = true
        splitError = nil
        defer { isUpdatingSplit = false }
        do {
            let remote = try await ExpensesAPIClient(baseURL: apiBaseURL).setSplit(
                transactionID: transaction.remoteID,
                fraction: fraction,
                customAmount: customAmount
            )
            transaction.splitFraction = remote.splitFraction
            transaction.customShareAmount = remote.customShareAmount
            try modelContext.save()
            customShareText = ""
            isShowingCustomShare = false
            isShowingSplitPicker = false
        } catch {
            splitError = "Could not save this split. Make sure the amount does not exceed the transaction total."
        }
    }
}

private struct SplitOptionButton: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private enum TransactionCategoryOption: String, CaseIterable, Identifiable {
    case groceries = "Groceries"
    case dining = "Dining"
    case shopping = "Shopping"
    case transport = "Transport"
    case travel = "Travel"
    case housing = "Housing"
    case utilities = "Utilities"
    case entertainment = "Entertainment"
    case health = "Health"
    case personalCare = "Personal Care"
    case homeImprovement = "Home Improvement"
    case services = "Services"
    case fees = "Fees"
    case loanPayments = "Loan Payments"
    case cardPayment = "Card Payment"
    case transfers = "Transfers"
    case income = "Income"
    case other = "Other"

    var id: String { rawValue }
}
