//
//  CashFlowDashboard.swift
//  Expenses
//

import Charts
import SwiftUI
import ExpensesCore

struct CashFlowDashboard: View {
    let transactions: [ExpensesCore.Transaction]
    let apiBaseURL: URL

    private let calendar = Calendar.current
    @State private var selectedSummaryMonth = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()

    private var currentMonthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
    }

    private var currentMonth: MonthCashFlow {
        cashFlow(for: Date())
    }

    private var monthHistory: [MonthCashFlow] {
        (0 ..< 4).reversed().compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: -offset, to: Date()) else { return nil }
            return cashFlow(for: month)
        }
    }

    private var summaryMonths: [MonthCashFlow] {
        (0 ..< 12).compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: -offset, to: currentMonthStart) else { return nil }
            return cashFlow(for: month)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                chartCard
                summaryCard
                categoryCard
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Color.expensesCanvas.ignoresSafeArea())
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Last 4 months")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Cash flow")
                        .font(.title2.bold())
                }
                Spacer()
                Image(systemName: "chart.xyaxis.line")
                    .font(.title3)
                    .foregroundStyle(Color.expensesGreen)
                    .padding(10)
                    .background(Color.expensesGreen.opacity(0.12), in: Circle())
            }

            Chart(monthHistory) { month in
                BarMark(
                    x: .value("Month", month.date, unit: .month),
                    y: .value("Income", month.income)
                )
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(Color.expensesMint.gradient)

                BarMark(
                    x: .value("Month", month.date, unit: .month),
                    y: .value("Expenses", -month.expenses)
                )
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(Color.expensesRose.gradient)

                LineMark(
                    x: .value("Month", month.date, unit: .month),
                    y: .value("Savings", month.savings)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .foregroundStyle(.primary)
            }
            .chartLegend(.hidden)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 190)
            .accessibilityLabel("Four month cash flow chart")
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var summaryCard: some View {
        TabView(selection: $selectedSummaryMonth) {
            ForEach(summaryMonths.reversed()) { month in
                summaryPage(for: month)
                    .tag(month.date)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 244)
        .accessibilityLabel("Swipe between monthly cash flow summaries")
    }

    private func summaryPage(for month: MonthCashFlow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(month.date.formatted(.dateTime.month(.wide).year()))
                .font(.title2.bold())
                .padding(.bottom, 16)

            NavigationLink {
                TransactionListView(transactions: transactions, initialFilter: .income, month: month.date)
            } label: {
                CashFlowMetric(title: "Income", amount: month.income, tint: .expensesGreen, symbol: "arrow.down.left", isInteractive: true)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 31)
            NavigationLink {
                TransactionListView(transactions: transactions, initialFilter: .expenses, month: month.date)
            } label: {
                CashFlowMetric(title: "Expenses", amount: month.expenses, tint: .expensesRed, symbol: "arrow.up.right", isInteractive: true)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 31)
            NavigationLink {
                TransactionListView(transactions: transactions, initialFilter: .savings, month: month.date)
            } label: {
                CashFlowMetric(title: "Savings", amount: month.savings, tint: .primary, symbol: "circle", isInteractive: true)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Spending this month")
                    .font(.title3.bold())
                Spacer()
                Text(currentMonth.expenses, format: .currency(code: "USD"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if categoryTotals.isEmpty {
                Text("Your spending categories will appear here after your first sync.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(categoryTotals) { category in
                    NavigationLink {
                        TransactionListView(transactions: transactions, initialFilter: .category(category.name))
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: category.symbol)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(category.tint)
                                .frame(width: 32, height: 32)
                                .background(category.tint.opacity(0.14), in: Circle())
                            Text(category.name)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(category.amount, format: .currency(code: "USD"))
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var categoryTotals: [CategoryTotal] {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let spending = transactions.filter {
            $0.date >= start && $0.amount > 0 && !$0.isPending && $0.countsTowardCashFlow
        }
        let grouped = Dictionary(grouping: spending, by: \ExpensesCore.Transaction.categoryName)

        return grouped.map { name, categoryTransactions in
            CategoryTotal(name: name, amount: categoryTransactions.reduce(0) { $0 + $1.amount })
        }
        .sorted { $0.amount > $1.amount }
        .prefix(4)
        .map { $0 }
    }

    private func cashFlow(for date: Date) -> MonthCashFlow {
        let relevant = transactions.filter {
            calendar.isDate($0.date, equalTo: date, toGranularity: .month)
                && !$0.isPending
                && $0.countsTowardCashFlow
        }
        let income = -relevant.filter { $0.amount < 0 }.reduce(0) { $0 + $1.amount }
        let expenses = relevant.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount }
        return MonthCashFlow(date: date, income: income, expenses: expenses)
    }
}

private struct MonthCashFlow: Identifiable {
    let date: Date
    let income: Double
    let expenses: Double

    var id: Date { date }
    var savings: Double { income - expenses }
}

private struct CategoryTotal: Identifiable {
    let name: String
    let amount: Double

    var id: String { name }

    var symbol: String {
        switch name.lowercased() {
        case let value where value.contains("food"), let value where value.contains("dining"):
            "fork.knife"
        case let value where value.contains("travel"), let value where value.contains("transport"):
            "car.fill"
        case let value where value.contains("shop"), let value where value.contains("retail"):
            "bag.fill"
        case let value where value.contains("bill"), let value where value.contains("utilit"):
            "bolt.fill"
        default:
            "square.grid.2x2.fill"
        }
    }

    var tint: Color {
        switch symbol {
        case "fork.knife": .orange
        case "car.fill": .blue
        case "bag.fill": .purple
        case "bolt.fill": .yellow
        default: .expensesGreen
        }
    }
}

private struct CashFlowMetric: View {
    let title: String
    let amount: Double
    let tint: Color
    let symbol: String
    let isInteractive: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(title)
                .font(.body)
            Spacer()
            Text(amount, format: .currency(code: "USD"))
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
            if isInteractive {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 15)
        .accessibilityElement(children: .combine)
    }
}

extension Color {
    static let expensesCanvas = Color(red: 0.96, green: 0.96, blue: 0.95)
    static let expensesGreen = Color(red: 0.10, green: 0.52, blue: 0.38)
    static let expensesMint = Color(red: 0.56, green: 0.82, blue: 0.69)
    static let expensesRed = Color(red: 0.84, green: 0.21, blue: 0.25)
    static let expensesRose = Color(red: 0.96, green: 0.61, blue: 0.64)
}
