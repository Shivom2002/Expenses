//
//  AnalyticsDashboard.swift
//  Expenses
//

import Charts
import SwiftUI
import ExpensesCore

struct AnalyticsDashboard: View {
    let transactions: [ExpensesCore.Transaction]

    private let calendar = Calendar.current
    @State private var selectedMonth = Date()

    private var selectedMonthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth)) ?? selectedMonth
    }

    private var selectedMonthTransactions: [ExpensesCore.Transaction] {
        transactions.filter {
            calendar.isDate($0.date, equalTo: selectedMonthStart, toGranularity: .month)
                && !$0.isPending
                && $0.countsTowardCashFlow
        }
    }

    private var currentIncome: Double {
        -selectedMonthTransactions.filter { $0.amount < 0 }.reduce(0) { $0 + $1.effectiveAmount }
    }

    private var currentExpenses: Double {
        selectedMonthTransactions.filter { $0.amount > 0 }.reduce(0) { $0 + $1.effectiveAmount }
    }

    private var savingsRate: Double? {
        guard currentIncome > 0 else { return nil }
        return (currentIncome - currentExpenses) / currentIncome
    }

    private var categoryBreakdown: [AnalyticsCategory] {
        let spending = selectedMonthTransactions.filter { $0.amount > 0 }
        let grouped = Dictionary(grouping: spending, by: \ExpensesCore.Transaction.categoryName)
        return grouped.map { name, transactions in
            AnalyticsCategory(name: name, amount: transactions.reduce(0) { $0 + $1.effectiveAmount })
        }
        .sorted { $0.amount > $1.amount }
    }

    private var monthlySpending: [MonthlySpending] {
        (0 ..< 6).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .month, value: -offset, to: selectedMonthStart) else { return nil }
            let total = transactions
                .filter {
                    calendar.isDate($0.date, equalTo: date, toGranularity: .month)
                        && $0.amount > 0
                        && !$0.isPending
                        && $0.countsTowardCashFlow
                }
                .reduce(0) { $0 + $1.effectiveAmount }
            return MonthlySpending(date: date, total: total)
        }
    }

    private var monthOptions: [Date] {
        let firstTransactionMonth = transactions
            .filter { !$0.isPending }
            .map(\.date)
            .min()
            .flatMap { calendar.date(from: calendar.dateComponents([.year, .month], from: $0)) }
        let oldestMonth = firstTransactionMonth ?? selectedMonthStart
        let latestMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let availableMonths = max(0, calendar.dateComponents([.month], from: oldestMonth, to: latestMonth).month ?? 0)

        return (0 ... min(availableMonths, 23)).compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: latestMonth)
        }
    }

    private var canAdvanceMonth: Bool {
        selectedMonthStart < (calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                monthPicker
                overviewCard

                if categoryBreakdown.isEmpty {
                    ContentUnavailableView(
                        "No spending data yet",
                        systemImage: "chart.pie",
                        description: Text("Connect a Sandbox institution to see your trends and category insights."))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    categoryCard
                    trendCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Color.expensesCanvas.ignoresSafeArea())
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.large)
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(selectedMonthStart.formatted(.dateTime.month(.wide).year()))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Savings rate")
                        .font(.headline)
                    if let savingsRate {
                        Text(savingsRate, format: .percent.precision(.fractionLength(0)))
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(savingsRate >= 0 ? Color.expensesGreen : Color.expensesRed)
                    } else {
                        Text("—")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Text(savingsRate == nil ? "Add income to calculate a rate" : "of this month’s income saved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.forward.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle((savingsRate ?? 0) >= 0 ? Color.expensesGreen : Color.expensesRed)
            }

            Divider()

            HStack {
                AnalyticsMetric(title: "Income", amount: currentIncome, tint: .expensesGreen)
                Divider().frame(height: 42)
                AnalyticsMetric(title: "Spent", amount: currentExpenses, tint: .expensesRed)
                Divider().frame(height: 42)
                AnalyticsMetric(title: "Saved", amount: currentIncome - currentExpenses, tint: .primary)
            }
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var monthPicker: some View {
        HStack {
            Button {
                selectedMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonthStart) ?? selectedMonth
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 38, height: 38)
            }
            .disabled(monthOptions.last.map { selectedMonthStart <= $0 } ?? true)

            Spacer()

            Menu {
                ForEach(monthOptions, id: \.self) { month in
                    Button(month.formatted(.dateTime.month(.wide).year())) {
                        selectedMonth = month
                    }
                }
            } label: {
                Label(selectedMonthStart.formatted(.dateTime.month(.wide).year()), systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Spacer()

            Button {
                selectedMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonthStart) ?? selectedMonth
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 38, height: 38)
            }
            .disabled(!canAdvanceMonth)
        }
        .padding(.horizontal, 4)
    }

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Where your money went")
                        .font(.title3.bold())
                    Text(selectedMonthStart.formatted(.dateTime.month(.wide).year()))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(currentExpenses, format: .currency(code: "USD"))
                    .font(.headline)
            }

            Chart(categoryBreakdown) { category in
                SectorMark(
                    angle: .value("Spent", category.amount),
                    innerRadius: .ratio(0.62),
                    angularInset: 2
                )
                .cornerRadius(5)
                .foregroundStyle(category.color)
            }
            .chartLegend(.hidden)
            .frame(height: 190)
            .overlay {
                VStack(spacing: 2) {
                    Text("Spent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(currentExpenses, format: .currency(code: "USD"))
                        .font(.headline.weight(.bold))
                }
            }

            ForEach(Array(categoryBreakdown.enumerated()), id: \.element.id) { index, category in
                NavigationLink {
                    TransactionListView(transactions: transactions, initialFilter: .category(category.name))
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(category.color)
                            .frame(width: 10, height: 10)
                        Text(category.name)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(category.amount, format: .currency(code: "USD"))
                            .font(.subheadline.weight(.semibold))
                        Text(category.percentage(of: currentExpenses), format: .percent.precision(.fractionLength(0)))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Spending trend")
                .font(.title3.bold())

            Chart(monthlySpending) { month in
                BarMark(
                    x: .value("Month", month.date, unit: .month),
                    y: .value("Spent", month.total)
                )
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(Color.expensesGreen.gradient)
                .annotation(position: .top) {
                    if month.date == monthlySpending.last?.date && month.total > 0 {
                        Text(month.total, format: .currency(code: "USD"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.quaternary)
                    AxisValueLabel(format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(.caption2)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) {
                    AxisValueLabel(format: .dateTime.month(.narrow))
                        .font(.caption.weight(.bold))
                }
            }
            .frame(height: 190)
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

private struct AnalyticsMetric: View {
    let title: String
    let amount: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(amount, format: .currency(code: "USD"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AnalyticsCategory: Identifiable {
    let name: String
    let amount: Double

    var id: String { name }

    var color: Color {
        switch name.lowercased() {
        case let value where value.contains("food"), let value where value.contains("dining"):
            .orange
        case let value where value.contains("travel"), let value where value.contains("transport"):
            .blue
        case let value where value.contains("shop"), let value where value.contains("retail"):
            .purple
        case let value where value.contains("bill"), let value where value.contains("utilit"):
            .yellow
        case let value where value.contains("housing"):
            .indigo
        default:
            .expensesGreen
        }
    }

    func percentage(of total: Double) -> Double {
        guard total > 0 else { return 0 }
        return amount / total
    }
}

private struct MonthlySpending: Identifiable {
    let date: Date
    let total: Double

    var id: Date { date }
}
