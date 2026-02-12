//
//  CostAnalyticsView.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import SwiftUI
import SwiftData
import Charts

/// Aggregated cost analytics dashboard showing spend over time, per-printer and per-resin breakdowns,
/// and budget-vs-actual tracking.
struct CostAnalyticsView: View {
    @Query(sort: \PrintJob.startDate, order: .reverse) private var allJobs: [PrintJob]
    @Query private var printers: [Printer]

    @AppStorage("resinCostPerMl") private var resinCostPerMl: Double = 0.0
    @AppStorage("resinCurrency") private var resinCurrency: String = "USD"
    @AppStorage("monthlyBudget") private var monthlyBudget: Double = 0.0

    @State private var timeRange: TimeRange = .month

    enum TimeRange: String, CaseIterable {
        case week = "7 Days"
        case month = "30 Days"
        case quarter = "90 Days"
        case year = "Year"

        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .quarter: return 90
            case .year: return 365
            }
        }

        var startDate: Date {
            Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        }
    }

    // MARK: - Computed Data

    private var completedJobs: [PrintJob] {
        allJobs.filter { $0.status == .completed }
    }

    private var jobsInRange: [PrintJob] {
        completedJobs.filter { $0.startDate >= timeRange.startDate }
    }

    private func costForJob(_ job: PrintJob) -> Double {
        guard let volume = job.model?.slicedVolumeMl, volume > 0 else { return 0 }
        // Use printer-specific cost if set, otherwise global
        let printerCost = printers.first(where: { $0.ipAddress == job.printerIP })?.resinCostPerMl
        let costPerMl = printerCost ?? resinCostPerMl
        guard costPerMl > 0 else { return 0 }
        return Double(volume) * costPerMl
    }

    private var totalCostInRange: Double {
        jobsInRange.reduce(0) { $0 + costForJob($1) }
    }

    private var totalCostAllTime: Double {
        completedJobs.reduce(0) { $0 + costForJob($1) }
    }

    private var totalVolumeInRange: Double {
        jobsInRange.reduce(0) { $0 + Double($1.model?.slicedVolumeMl ?? 0) }
    }

    private var averageCostPerJob: Double {
        let jobsWithCost = jobsInRange.filter { costForJob($0) > 0 }
        guard !jobsWithCost.isEmpty else { return 0 }
        return jobsWithCost.reduce(0) { $0 + costForJob($1) } / Double(jobsWithCost.count)
    }

    /// Current month's spend for budget tracking
    private var currentMonthSpend: Double {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        return completedJobs
            .filter { $0.startDate >= start }
            .reduce(0) { $0 + costForJob($1) }
    }

    /// Spend grouped by day for the chart
    private var dailySpend: [(date: Date, cost: Double)] {
        let cal = Calendar.current
        var byDay: [Date: Double] = [:]

        for job in jobsInRange {
            let day = cal.startOfDay(for: job.startDate)
            byDay[day, default: 0] += costForJob(job)
        }

        return byDay.sorted { $0.key < $1.key }.map { (date: $0.key, cost: $0.value) }
    }

    /// Spend grouped by printer
    private var perPrinterSpend: [(name: String, cost: Double)] {
        var byPrinter: [String: Double] = [:]
        for job in jobsInRange {
            let name = job.printerName
            byPrinter[name, default: 0] += costForJob(job)
        }
        return byPrinter.sorted { $0.value > $1.value }.map { (name: $0.key, cost: $0.value) }
    }

    /// Spend grouped by resin profile
    private var perResinSpend: [(name: String, cost: Double)] {
        var byResin: [String: Double] = [:]
        for job in jobsInRange {
            let name = job.resinProfile?.name ?? "Unknown"
            byResin[name, default: 0] += costForJob(job)
        }
        return byResin.sorted { $0.value > $1.value }.map { (name: $0.key, cost: $0.value) }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Time range picker
                Picker("Range", selection: $timeRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Summary cards
                summaryCards

                // Budget tracker
                if monthlyBudget > 0 {
                    budgetCard
                }

                // Spend over time chart
                if !dailySpend.isEmpty {
                    spendOverTimeChart
                }

                // Per-printer breakdown
                if perPrinterSpend.count > 1 {
                    perPrinterChart
                }

                // Per-resin breakdown
                if perResinSpend.count > 1 {
                    perResinChart
                }

                // Top cost jobs table
                topCostJobs

                Spacer(minLength: 20)
            }
            .padding(.top)
        }
        .navigationTitle("Cost Analytics")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            costCard(
                title: "Period Spend",
                value: formatCost(totalCostInRange),
                icon: "creditcard",
                color: .blue
            )
            costCard(
                title: "Avg per Job",
                value: formatCost(averageCostPerJob),
                icon: "chart.bar",
                color: .green
            )
            costCard(
                title: "Total Volume",
                value: String(format: "%.0f mL", totalVolumeInRange),
                icon: "drop.fill",
                color: .cyan
            )
            costCard(
                title: "All-time Spend",
                value: formatCost(totalCostAllTime),
                icon: "banknote",
                color: .purple
            )
        }
        .padding(.horizontal)
    }

    private func costCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.caption)
                Spacer()
            }
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Budget Card

    private var budgetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Monthly Budget", systemImage: "target")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(formatCost(monthlyBudget))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            let ratio = min(currentMonthSpend / monthlyBudget, 1.5)
            let isOver = currentMonthSpend > monthlyBudget

            ProgressView(value: min(ratio, 1.0)) {
                HStack {
                    Text("Spent: \(formatCost(currentMonthSpend))")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(isOver ? .red : .primary)
                    Spacer()
                    Text(isOver ? "Over budget!" : "\(formatCost(monthlyBudget - currentMonthSpend)) remaining")
                        .font(.caption)
                        .foregroundStyle(isOver ? .red : .green)
                }
            }
            .tint(isOver ? .red : .blue)
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Spend Over Time Chart

    private var spendOverTimeChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Spending Over Time", systemImage: "chart.line.uptrend.xyaxis")
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal)

            Chart(dailySpend, id: \.date) { entry in
                BarMark(
                    x: .value("Date", entry.date, unit: .day),
                    y: .value("Cost", entry.cost)
                )
                .foregroundStyle(.blue.gradient)
                .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(formatCostShort(v))
                        }
                    }
                }
            }
            .frame(height: 180)
            .padding(.horizontal)
        }
    }

    // MARK: - Per-Printer Chart

    private var perPrinterChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("By Printer", systemImage: "printer.fill")
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal)

            Chart(perPrinterSpend, id: \.name) { entry in
                SectorMark(
                    angle: .value("Cost", entry.cost),
                    innerRadius: .ratio(0.5),
                    angularInset: 1.5
                )
                .foregroundStyle(by: .value("Printer", entry.name))
                .cornerRadius(4)
            }
            .chartLegend(position: .bottom)
            .frame(height: 200)
            .padding(.horizontal)
        }
    }

    // MARK: - Per-Resin Chart

    private var perResinChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("By Material", systemImage: "drop.fill")
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal)

            Chart(perResinSpend, id: \.name) { entry in
                BarMark(
                    x: .value("Cost", entry.cost),
                    y: .value("Material", entry.name)
                )
                .foregroundStyle(.cyan.gradient)
                .cornerRadius(4)
                .annotation(position: .trailing) {
                    Text(formatCostShort(entry.cost))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: CGFloat(perResinSpend.count) * 40 + 20)
            .padding(.horizontal)
        }
    }

    // MARK: - Top Cost Jobs

    private var topCostJobs: some View {
        let jobsWithCost = jobsInRange
            .map { (job: $0, cost: costForJob($0)) }
            .filter { $0.cost > 0 }
            .sorted { $0.cost > $1.cost }
            .prefix(5)

        return Group {
            if !jobsWithCost.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Top Cost Prints", systemImage: "arrow.up.right.circle")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal)

                    VStack(spacing: 6) {
                        ForEach(Array(jobsWithCost.enumerated()), id: \.element.job.id) { index, entry in
                            HStack(spacing: 12) {
                                Text("#\(index + 1)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.job.model?.name ?? entry.job.fileName ?? "Unknown")
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Text(entry.job.printerName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(formatCost(entry.cost))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.blue)
                            }
                            .padding(.horizontal)

                            if index < jobsWithCost.count - 1 {
                                Divider().padding(.horizontal)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
            }
        }
    }

    // MARK: - Formatting

    private var currencySymbol: String {
        switch resinCurrency {
        case "EUR": return "\u{20AC}"
        case "GBP": return "\u{00A3}"
        case "JPY": return "\u{00A5}"
        case "CAD": return "CA$"
        case "AUD": return "A$"
        default: return "$"
        }
    }

    private func formatCost(_ value: Double) -> String {
        "\(currencySymbol)\(String(format: "%.2f", value))"
    }

    private func formatCostShort(_ value: Double) -> String {
        if value >= 1000 {
            return "\(currencySymbol)\(String(format: "%.0fk", value / 1000))"
        }
        return "\(currencySymbol)\(String(format: "%.0f", value))"
    }
}
