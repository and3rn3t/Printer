//
//  StatisticsView.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import SwiftUI
import SwiftData
import Charts

/// Dashboard view displaying print statistics and analytics.
///
/// Shows summary cards, success rate, print activity over time,
/// per-printer breakdowns, and resin usage.
struct StatisticsView: View {
    @Query(sort: \PrintJob.startDate, order: .reverse) private var allJobs: [PrintJob]
    @Query private var models: [PrintModel]
    @Query private var printers: [Printer]

    @State private var timeRange: TimeRange = .month

    enum TimeRange: String, CaseIterable {
        case week = "7 Days"
        case month = "30 Days"
        case year = "Year"
        case all = "All Time"

        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .year: return 365
            case .all: return 36500
            }
        }

        var startDate: Date {
            Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        }
    }

    private var filteredJobs: [PrintJob] {
        allJobs.filter { $0.startDate >= timeRange.startDate }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Time range picker
                Picker("Time Range", selection: $timeRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Summary cards
                summaryCards

                // Success rate chart
                if !filteredJobs.isEmpty {
                    successRateChart

                    // Activity over time
                    activityChart

                    // Per-printer breakdown
                    printerBreakdown

                    // Resin usage (if any models have volume data)
                    if totalResinMl > 0 {
                        resinUsageSection
                    }
                }

                if filteredJobs.isEmpty {
                    ContentUnavailableView(
                        "No Print Data",
                        systemImage: "chart.bar.xaxis",
                        description: Text("Print jobs will appear here once you start printing")
                    )
                    .padding(.top, 40)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Statistics")
    }

    // MARK: - Summary Cards

    @ViewBuilder
    private var summaryCards: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            StatCard(
                title: "Total Prints",
                value: "\(filteredJobs.count)",
                icon: "printer.fill",
                color: .blue
            )

            StatCard(
                title: "Completed",
                value: "\(completedCount)",
                icon: "checkmark.circle.fill",
                color: .green
            )

            StatCard(
                title: "Print Time",
                value: totalPrintTimeFormatted,
                icon: "clock.fill",
                color: .purple
            )

            StatCard(
                title: "Models",
                value: "\(models.count)",
                icon: "cube.fill",
                color: .orange
            )

            if totalEstimatedCost > 0 {
                StatCard(
                    title: "Est. Cost",
                    value: formattedTotalCost,
                    icon: "dollarsign.circle.fill",
                    color: .green
                )
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Success Rate Chart

    @ViewBuilder
    private var successRateChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Success Rate")
                .font(.headline)
                .padding(.horizontal)

            HStack(spacing: 16) {
                // Donut chart
                Chart(statusBreakdown, id: \.status) { item in
                    SectorMark(
                        angle: .value("Count", item.count),
                        innerRadius: .ratio(0.6),
                        angularInset: 2
                    )
                    .foregroundStyle(item.color)
                    .cornerRadius(4)
                }
                .frame(width: 120, height: 120)

                // Legend
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(statusBreakdown, id: \.status) { item in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(item.color)
                                .frame(width: 10, height: 10)
                            Text(item.status)
                                .font(.caption)
                            Spacer()
                            Text("\(item.count)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if filteredJobs.count > 0 {
                        Divider()
                        Text("\(successRate)% success rate")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.green)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Activity Chart

    @ViewBuilder
    private var activityChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Print Activity")
                .font(.headline)
                .padding(.horizontal)

            Chart(dailyActivity, id: \.date) { item in
                BarMark(
                    x: .value("Date", item.date, unit: chartUnit),
                    y: .value("Prints", item.count)
                )
                .foregroundStyle(.blue.gradient)
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: chartDateFormat)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 160)
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Printer Breakdown

    @ViewBuilder
    private var printerBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By Printer")
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 8) {
                ForEach(printerStats, id: \.name) { stat in
                    HStack(spacing: 12) {
                        Image(systemName: "printer.fill")
                            .font(.callout)
                            .foregroundStyle(.blue)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(stat.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("\(stat.count) prints · \(stat.formattedTime)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // Proportion bar
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.blue.opacity(0.2))
                                .frame(width: geo.size.width)
                                .overlay(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(.blue.gradient)
                                        .frame(width: geo.size.width * stat.proportion)
                                }
                        }
                        .frame(width: 80, height: 6)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Resin Usage

    @ViewBuilder
    private var resinUsageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Material Usage")
                .font(.headline)
                .padding(.horizontal)

            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Image(systemName: "drop.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    Text(String(format: "%.1f mL", totalResinMl))
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("Resin Used")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 4) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.title2)
                        .foregroundStyle(.purple)
                    Text("\(totalLayers)")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("Total Layers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 4) {
                    Image(systemName: "arrow.up.and.down")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text(String(format: "%.1f mm", totalPrintHeightMm))
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("Print Height")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Computed Data

    private var completedCount: Int {
        filteredJobs.filter { $0.status == .completed }.count
    }

    private var successRate: Int {
        let finished = filteredJobs.filter { $0.status == .completed || $0.status == .failed || $0.status == .cancelled }
        guard !finished.isEmpty else { return 0 }
        return Int(Double(completedCount) / Double(finished.count) * 100)
    }

    private var totalPrintTimeFormatted: String {
        let total = filteredJobs.reduce(0.0) { $0 + $1.effectiveDuration }
        return formatDuration(total)
    }

    private struct StatusData {
        let status: String
        let count: Int
        let color: Color
    }

    private var statusBreakdown: [StatusData] {
        let completed = filteredJobs.filter { $0.status == .completed }.count
        let failed = filteredJobs.filter { $0.status == .failed }.count
        let cancelled = filteredJobs.filter { $0.status == .cancelled }.count
        let active = filteredJobs.filter {
            $0.status == .printing || $0.status == .uploading
                || $0.status == .preparing || $0.status == .queued
        }.count

        var result: [StatusData] = []
        if completed > 0 { result.append(StatusData(status: "Completed", count: completed, color: .green)) }
        if failed > 0 { result.append(StatusData(status: "Failed", count: failed, color: .red)) }
        if cancelled > 0 { result.append(StatusData(status: "Cancelled", count: cancelled, color: .gray)) }
        if active > 0 { result.append(StatusData(status: "Active", count: active, color: .blue)) }
        return result
    }

    private struct DailyActivity {
        let date: Date
        let count: Int
    }

    private var dailyActivity: [DailyActivity] {
        let calendar = Calendar.current
        var grouped: [Date: Int] = [:]

        for job in filteredJobs {
            let day = calendar.startOfDay(for: job.startDate)
            grouped[day, default: 0] += 1
        }

        return grouped.map { DailyActivity(date: $0.key, count: $0.value) }
            .sorted { $0.date < $1.date }
    }

    private var chartUnit: Calendar.Component {
        switch timeRange {
        case .week: return .day
        case .month: return .day
        case .year: return .month
        case .all: return .month
        }
    }

    private var chartDateFormat: Date.FormatStyle {
        switch timeRange {
        case .week, .month: return .dateTime.day().month(.abbreviated)
        case .year, .all: return .dateTime.month(.abbreviated)
        }
    }

    private struct PrinterStat {
        let name: String
        let count: Int
        let totalTime: TimeInterval
        let proportion: Double

        var formattedTime: String {
            formatDuration(totalTime)
        }
    }

    private var printerStats: [PrinterStat] {
        var grouped: [String: (count: Int, time: TimeInterval)] = [:]

        for job in filteredJobs {
            let name = job.printerName
            var entry = grouped[name, default: (0, 0)]
            entry.count += 1
            entry.time += job.effectiveDuration
            grouped[name] = entry
        }

        let maxCount = grouped.values.map(\.count).max() ?? 1
        return grouped.map { name, data in
            PrinterStat(
                name: name,
                count: data.count,
                totalTime: data.time,
                proportion: Double(data.count) / Double(maxCount)
            )
        }
        .sorted { $0.count > $1.count }
    }

    private var totalResinMl: Float {
        // Sum up resin volume from completed print jobs that have model metadata
        filteredJobs
            .filter { $0.status == .completed }
            .compactMap { $0.model?.slicedVolumeMl }
            .reduce(0, +)
    }

    private var totalLayers: Int {
        filteredJobs
            .filter { $0.status == .completed }
            .compactMap { $0.model?.slicedLayerCount }
            .reduce(0, +)
    }

    private var totalPrintHeightMm: Float {
        filteredJobs
            .filter { $0.status == .completed }
            .compactMap { $0.model?.slicedPrintHeight }
            .reduce(0, +)
    }

    /// Total estimated cost based on resin volume and cost per mL
    private var totalEstimatedCost: Double {
        let costPerMl = UserDefaults.standard.double(forKey: "resinCostPerMl")
        guard costPerMl > 0 else { return 0 }
        let totalVolume = filteredJobs
            .filter { $0.status == .completed }
            .compactMap { $0.model?.slicedVolumeMl }
            .reduce(Float(0), +)
        return Double(totalVolume) * costPerMl
    }

    private var formattedTotalCost: String {
        let currency = UserDefaults.standard.string(forKey: "resinCurrency") ?? "USD"
        let symbol: String
        switch currency {
        case "EUR": symbol = "\u{20AC}"
        case "GBP": symbol = "\u{00A3}"
        case "JPY": symbol = "\u{00A5}"
        case "CAD": symbol = "CA$"
        case "AUD": symbol = "A$"
        default: symbol = "$"
        }
        return "\(symbol)\(String(format: "%.2f", totalEstimatedCost))"
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.callout)
                    .foregroundStyle(color)
                Spacer()
            }

            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.background)
                .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
    }
}

#Preview {
    NavigationStack {
        StatisticsView()
    }
    .modelContainer(for: [PrintModel.self, PrintJob.self, Printer.self], inMemory: true)
}
