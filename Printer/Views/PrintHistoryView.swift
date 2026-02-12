//
//  PrintHistoryView.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import SwiftUI
import SwiftData
import Charts

/// Browsable list of all print jobs across all printers.
///
/// Supports filtering by status and sorting by date. Shows duration, printer name,
/// file name, status badges, and interactive charts for each job.
struct PrintHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PrintJob.startDate, order: .reverse) private var allJobs: [PrintJob]

    @State private var statusFilter: StatusFilter = .all
    @State private var searchText = ""
    @State private var chartRange: ChartRange = .month
    @State private var annotatingJob: PrintJob?
    @State private var retryJob: PrintJob?
    @State private var exportURL: URL?
    @State private var showingExportShare = false

    // MARK: - Filter Types

    enum StatusFilter: String, CaseIterable {
        case all = "All"
        case active = "Active"
        case completed = "Completed"
        case failed = "Failed"

        var icon: String {
            switch self {
            case .all: return "list.bullet"
            case .active: return "printer.fill"
            case .completed: return "checkmark.circle"
            case .failed: return "xmark.circle"
            }
        }
    }

    enum ChartRange: String, CaseIterable {
        case week = "7 Days"
        case month = "30 Days"
        case year = "Year"

        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .year: return 365
            }
        }

        var startDate: Date {
            Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        }

        /// Calendar component used for grouping dates in charts
        var groupingComponent: Calendar.Component {
            switch self {
            case .week, .month: return .day
            case .year: return .month
            }
        }
    }

    // MARK: - Chart Data Types

    struct DailyPrintData: Identifiable {
        let id = UUID()
        let date: Date
        let status: String
        let count: Int
        let color: Color
    }

    struct DurationData: Identifiable {
        let id = UUID()
        let date: Date
        let hours: Double
    }

    // MARK: - Computed Properties

    var filteredJobs: [PrintJob] {
        var jobs = allJobs

        switch statusFilter {
        case .all:
            break
        case .active:
            jobs = jobs.filter {
                $0.status == .printing || $0.status == .uploading
                    || $0.status == .preparing || $0.status == .queued
            }
        case .completed:
            jobs = jobs.filter { $0.status == .completed }
        case .failed:
            jobs = jobs.filter { $0.status == .failed || $0.status == .cancelled }
        }

        if !searchText.isEmpty {
            jobs = jobs.filter {
                $0.printerName.localizedCaseInsensitiveContains(searchText)
                    || ($0.fileName ?? "").localizedCaseInsensitiveContains(searchText)
                    || ($0.model?.name ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }

        return jobs
    }

    /// Jobs within the selected chart time range
    private var chartJobs: [PrintJob] {
        allJobs.filter { $0.startDate >= chartRange.startDate }
    }

    /// Activity data grouped by date and status for the stacked bar chart
    private var activityData: [DailyPrintData] {
        let calendar = Calendar.current
        let component = chartRange.groupingComponent

        let grouped = Dictionary(grouping: chartJobs) { job in
            calendar.dateInterval(of: component, for: job.startDate)?.start ?? job.startDate
        }

        var result: [DailyPrintData] = []
        for (date, jobs) in grouped {
            let completed = jobs.filter { $0.status == .completed }.count
            let failed = jobs.filter { $0.status == .failed || $0.status == .cancelled }.count
            let other = jobs.count - completed - failed

            if completed > 0 {
                result.append(DailyPrintData(date: date, status: "Completed", count: completed, color: .green))
            }
            if failed > 0 {
                result.append(DailyPrintData(date: date, status: "Failed", count: failed, color: .red))
            }
            if other > 0 {
                result.append(DailyPrintData(date: date, status: "Other", count: other, color: .orange))
            }
        }

        return result.sorted { $0.date < $1.date }
    }

    /// Print duration data grouped by date for the duration chart
    private var durationData: [DurationData] {
        let calendar = Calendar.current
        let component = chartRange.groupingComponent

        let grouped = Dictionary(grouping: chartJobs) { job in
            calendar.dateInterval(of: component, for: job.startDate)?.start ?? job.startDate
        }

        return grouped.map { date, jobs in
            let totalHours = jobs.reduce(0.0) { $0 + $1.effectiveDuration } / 3600.0
            return DurationData(date: date, hours: totalHours)
        }
        .sorted { $0.date < $1.date }
    }

    /// Success rate as a percentage (0–100)
    private var successRate: Double {
        let finished = allJobs.filter {
            $0.status == .completed || $0.status == .failed || $0.status == .cancelled
        }
        guard !finished.isEmpty else { return 0 }
        let completed = finished.filter { $0.status == .completed }.count
        return Double(completed) / Double(finished.count) * 100
    }

    // MARK: - Body

    var body: some View {
        Group {
            if allJobs.isEmpty {
                ContentUnavailableView(
                    "No Print History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Print jobs will appear here as you use your printers")
                )
            } else {
                List {
                    // Summary section
                    summarySection

                    // Charts section
                    chartsSection

                    // Jobs list
                    Section {
                        ForEach(filteredJobs) { job in
                            PrintHistoryRowView(job: job)
                                .swipeActions(edge: .trailing) {
                                    if job.status == .failed {
                                        Button {
                                            annotatingJob = job
                                        } label: {
                                            Label("Annotate", systemImage: "pencil")
                                        }
                                        .tint(.orange)
                                    }

                                    if job.status == .failed || job.status == .cancelled {
                                        Button {
                                            retryJob = job
                                        } label: {
                                            Label("Retry", systemImage: "arrow.clockwise")
                                        }
                                        .tint(.blue)
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        shareJobReport(job)
                                    } label: {
                                        Label("Report", systemImage: "doc.text")
                                    }
                                    .tint(.green)
                                }
                        }
                        .onDelete(perform: deleteJobs)
                    } header: {
                        HStack {
                            Text("Jobs")
                            Spacer()
                            Text("\(filteredJobs.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Search by name, file, or printer")
            }
        }
        .navigationTitle("Print History")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(StatusFilter.allCases, id: \.self) { filter in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                statusFilter = filter
                            }
                        } label: {
                            Label(filter.rawValue, systemImage: filter.icon)
                        }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
            }

            ToolbarItem(placement: .secondaryAction) {
                Button {
                    exportToCSV()
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showingExportShare) {
            if let url = exportURL {
                ShareSheetView(items: [url])
            }
        }
        .sheet(item: $annotatingJob) { job in
            FailureAnnotationView(job: job)
        }
        .sheet(item: $retryJob) { job in
            if let model = job.model {
                PrintJobView(model: model, printers: retryPrinters(for: job))
            }
        }
    }

    /// Build a printer list for retry
    private func retryPrinters(for job: PrintJob) -> [Printer] {
        let descriptor = FetchDescriptor<Printer>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Export filtered jobs to CSV and show share sheet
    private func exportToCSV() {
        Task {
            let exporter = ExportService()
            let csv = await exporter.exportJobsToCSV(jobs: filteredJobs)
            let dateStr = Date().formatted(.dateTime.year().month().day())
            if let url = await exporter.writeToTempFile(content: csv, fileName: "PrintHistory_\(dateStr).csv") {
                await MainActor.run {
                    exportURL = url
                    showingExportShare = true
                }
            }
        }
    }

    /// Generate and share a print report for a single job
    private func shareJobReport(_ job: PrintJob) {
        Task {
            let exporter = ExportService()
            let report = await exporter.generatePrintReport(job: job)
            let fileName = "\(job.model?.name ?? "Print")_report.txt"
            if let url = await exporter.writeToTempFile(content: report, fileName: fileName) {
                await MainActor.run {
                    exportURL = url
                    showingExportShare = true
                }
            }
        }
    }

    // MARK: - Summary

    @ViewBuilder
    private var summarySection: some View {
        Section {
            HStack(spacing: 0) {
                summaryStat(
                    value: "\(allJobs.count)",
                    label: "Total",
                    color: .blue
                )

                Divider()
                    .frame(height: 40)

                summaryStat(
                    value: "\(allJobs.filter { $0.status == .completed }.count)",
                    label: "Completed",
                    color: .green
                )

                Divider()
                    .frame(height: 40)

                summaryStat(
                    value: String(format: "%.0f%%", successRate),
                    label: "Success",
                    color: successRate >= 80 ? .green : (successRate >= 50 ? .orange : .red)
                )

                Divider()
                    .frame(height: 40)

                summaryStat(
                    value: totalPrintTime,
                    label: "Print Time",
                    color: .purple
                )
            }
        }
    }

    @ViewBuilder
    private func summaryStat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var totalPrintTime: String {
        let total = allJobs.reduce(0.0) { $0 + $1.effectiveDuration }
        return formatDuration(total)
    }

    // MARK: - Charts

    @ViewBuilder
    private var chartsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                // Time range picker
                Picker("Range", selection: $chartRange.animation(.easeInOut(duration: 0.3))) {
                    ForEach(ChartRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                // Activity chart — stacked bar showing prints per day/month by status
                if !activityData.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Print Activity", systemImage: "chart.bar.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Chart(activityData) { item in
                            BarMark(
                                x: .value("Date", item.date, unit: chartRange.groupingComponent),
                                y: .value("Prints", item.count)
                            )
                            .foregroundStyle(by: .value("Status", item.status))
                        }
                        .chartForegroundStyleScale([
                            "Completed": Color.green,
                            "Failed": Color.red,
                            "Other": Color.orange
                        ])
                        .chartLegend(position: .bottom, spacing: 12)
                        .chartYAxis {
                            AxisMarks(preset: .aligned) { _ in
                                AxisGridLine()
                                AxisValueLabel()
                            }
                        }
                        .frame(height: 180)
                    }
                }

                // Duration chart — total print hours per day/month
                if !durationData.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Print Duration", systemImage: "clock.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Chart(durationData) { item in
                            AreaMark(
                                x: .value("Date", item.date, unit: chartRange.groupingComponent),
                                y: .value("Hours", item.hours)
                            )
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [.purple.opacity(0.6), .purple.opacity(0.1)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)

                            LineMark(
                                x: .value("Date", item.date, unit: chartRange.groupingComponent),
                                y: .value("Hours", item.hours)
                            )
                            .foregroundStyle(.purple)
                            .interpolationMethod(.catmullRom)
                        }
                        .chartYAxis {
                            AxisMarks(preset: .aligned) { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let hours = value.as(Double.self) {
                                        Text(String(format: "%.1fh", hours))
                                    }
                                }
                            }
                        }
                        .frame(height: 150)
                    }
                }

                // Empty state for charts
                if activityData.isEmpty {
                    ContentUnavailableView {
                        Label("No Activity", systemImage: "chart.bar")
                    } description: {
                        Text("No prints in the selected time range")
                    }
                    .frame(height: 120)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Charts")
        }
    }

    // MARK: - Actions

    private func deleteJobs(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(filteredJobs[index])
            }
        }
    }
}

// MARK: - Print History Row

struct PrintHistoryRowView: View {
    let job: PrintJob
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: statusIcon)
                    .font(.system(size: 16))
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                // Primary: model name or file name
                Text(job.model?.name ?? job.fileName ?? "Unknown File")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                // Secondary: printer + date
                HStack(spacing: 6) {
                    Image(systemName: "printer")
                        .font(.caption2)
                    Text(job.printerName)
                        .font(.caption)

                    Text("·")
                        .foregroundStyle(.tertiary)

                    Text(job.startDate.formatted(.relative(presentation: .named)))
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

                // Duration
                if job.effectiveDuration > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text(job.formattedDuration)
                            .font(.caption)

                        if let cost = estimatedCost {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Image(systemName: "dollarsign.circle")
                                .font(.caption2)
                            Text(cost)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                    .foregroundStyle(.secondary)
                }

                // Failure annotation
                if job.status == .failed, let reason = job.failureReason {
                    HStack(spacing: 4) {
                        Image(systemName: reason.icon)
                            .font(.caption2)
                        Text(reason.rawValue)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.red.opacity(0.8))
                }
            }

            Spacer()

            // Photo log badge
            PhotoLogBadge(count: snapshotCount)

            // Status badge
            Text(statusText)
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.12))
                .foregroundStyle(statusColor)
                .clipShape(Capsule())
        }
        .padding(.vertical, 2)
        .onAppear { loadSnapshotCount() }
    }

    /// Count of snapshots for this job (fetched on appear)
    @State private var snapshotCount: Int = 0

    private func loadSnapshotCount() {
        let jobID = job.id
        let descriptor = FetchDescriptor<PrintSnapshot>(
            predicate: #Predicate { $0.printJob?.id == jobID }
        )
        snapshotCount = (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    // MARK: - Status Styling

    private var statusIcon: String { job.status.icon }
    private var statusColor: Color { job.status.color }
    private var statusText: String { job.status.displayText }

    /// Estimated cost based on resin volume and cost per mL
    private var estimatedCost: String? {
        guard let volume = job.model?.slicedVolumeMl, volume > 0 else { return nil }
        let costPerMl = UserDefaults.standard.double(forKey: "resinCostPerMl")
        guard costPerMl > 0 else { return nil }
        let cost = Double(volume) * costPerMl
        let currency = UserDefaults.standard.string(forKey: "resinCurrency") ?? "USD"
        return formatCostString(cost, currency: currency)
    }

    private func formatCostString(_ cost: Double, currency: String) -> String {
        let symbol: String
        switch currency {
        case "EUR": symbol = "\u{20AC}"
        case "GBP": symbol = "\u{00A3}"
        case "JPY": symbol = "\u{00A5}"
        case "CAD": symbol = "CA$"
        case "AUD": symbol = "A$"
        default: symbol = "$"
        }
        return "\(symbol)\(String(format: "%.2f", cost))"
    }
}
