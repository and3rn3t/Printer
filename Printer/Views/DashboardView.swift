//
//  DashboardView.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import OSLog
import SwiftData
import SwiftUI

/// Single-glance dashboard showing all printers' live status, active prints, and recent activity.
struct DashboardView: View {
    @Query private var printers: [Printer]
    @Environment(\.modelContext) private var modelContext

    @State private var printerStates: [UUID: PrinterLiveState] = [:]
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var refreshTask: Task<Void, Never>?

    // Cached stats — computed once per refresh, not per body evaluation
    @State private var cachedRecentJobs: [PrintJob] = []
    @State private var cachedModelCount: Int = 0
    @State private var cachedJobCount: Int = 0
    @State private var cachedSuccessRate: String = "—"
    @State private var cachedTotalSpendThisMonth: Double = 0
    @State private var cachedMaintenanceAlerts: [MaintenanceScheduler.MaintenanceAlert] = []

    /// Live state for a printer card
    struct PrinterLiveState {
        var isReachable: Bool?
        var photonStatus: PhotonPrinterService.PhotonStatus?
        var progress: Double?
        var fileName: String?
        var currentLayer: Int?
        var totalLayers: Int?
        var estimatedTimeRemaining: TimeInterval?
        var estimatedCompletionDate: Date?
    }

    /// Printers currently printing (derived from live state, lightweight)
    private var activePrinters: [Printer] {
        printers.filter { printer in
            if let state = printerStates[printer.id] {
                if let status = state.photonStatus, status == .printing || status == .paused {
                    return true
                }
                if let progress = state.progress, progress > 0, progress < 1.0 {
                    return true
                }
            }
            return false
        }
    }

    /// Refresh cached stats from SwiftData using targeted queries
    private func refreshCachedStats() {
        do {
            // Recent jobs — fetch only terminal statuses with limit
            var recentDescriptor = FetchDescriptor<PrintJob>(
                sortBy: [SortDescriptor(\PrintJob.startDate, order: .reverse)]
            )
            recentDescriptor.fetchLimit = 20
            let recentCandidates = try modelContext.fetch(recentDescriptor)
            cachedRecentJobs = Array(
                recentCandidates
                    .filter { $0.status == .completed || $0.status == .failed || $0.status == .cancelled }
                    .prefix(5)
            )

            // Counts
            cachedModelCount = (try? modelContext.fetchCount(FetchDescriptor<PrintModel>())) ?? 0
            cachedJobCount = (try? modelContext.fetchCount(FetchDescriptor<PrintJob>())) ?? 0

            // Success rate
            let allJobs = try modelContext.fetch(FetchDescriptor<PrintJob>())
            let completed = allJobs.filter { $0.status == .completed }.count
            let total = allJobs.filter { $0.status == .completed || $0.status == .failed }.count
            cachedSuccessRate = total > 0 ? "\(Int(Double(completed) / Double(total) * 100))%" : "—"

            // Monthly spend
            let cal = Calendar.current
            let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
            let resinCost = resinCostPerMl
            if resinCost > 0 {
                cachedTotalSpendThisMonth = allJobs
                    .filter { $0.status == .completed && $0.startDate >= monthStart }
                    .reduce(0) { sum, job in
                        sum + Double(job.model?.slicedVolumeMl ?? 0) * resinCost
                    }
            } else {
                cachedTotalSpendThisMonth = 0
            }

            // Maintenance
            cachedMaintenanceAlerts = MaintenanceScheduler.computeAlerts(printers: printers)
        } catch {
            AppLogger.data.warning("Failed to refresh dashboard stats: \(error.localizedDescription)")
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Active prints hero
                if !activePrinters.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Active Prints", systemImage: "printer.fill")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(activePrinters) { printer in
                            if let state = printerStates[printer.id] {
                                activePrintCard(printer: printer, state: state)
                            }
                        }
                    }
                }

                // Printer status grid
                VStack(alignment: .leading, spacing: 12) {
                    Label("Printers", systemImage: "network")
                        .font(.headline)
                        .padding(.horizontal)

                    if printers.isEmpty {
                        ContentUnavailableView(
                            "No Printers",
                            systemImage: "printer.slash",
                            description: Text("Add a printer to see its status here")
                        )
                        .frame(height: 200)
                    } else {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12),
                            ], spacing: 12
                        ) {
                            ForEach(printers) { printer in
                                printerStatusCard(printer: printer)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // Maintenance alerts
                if !cachedMaintenanceAlerts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Maintenance Due", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                            .padding(.horizontal)

                        VStack(spacing: 6) {
                            ForEach(cachedMaintenanceAlerts.prefix(3)) { alert in
                                HStack(spacing: 10) {
                                    Image(systemName: alert.type.icon)
                                        .foregroundStyle(alert.isOverdue ? .red : .orange)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(alert.type.rawValue)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text(alert.printerName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(alert.displayText)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(alert.isOverdue ? .red : .orange)
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical, 8)
                        .background(
                            Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 12)
                        )
                        .padding(.horizontal)
                    }
                }

                // Quick stats
                VStack(alignment: .leading, spacing: 12) {
                    Label("Quick Stats", systemImage: "chart.bar.fill")
                        .font(.headline)
                        .padding(.horizontal)

                    HStack(spacing: 12) {
                        quickStatCard(
                            title: "Models",
                            value: "\(cachedModelCount)",
                            icon: "cube.transparent",
                            color: .blue
                        )
                        quickStatCard(
                            title: "Print Jobs",
                            value: "\(cachedJobCount)",
                            icon: "printer.fill",
                            color: .green
                        )
                        quickStatCard(
                            title: "Success Rate",
                            value: cachedSuccessRate,
                            icon: "checkmark.seal.fill",
                            color: .purple
                        )
                    }
                    .padding(.horizontal)

                    // Cost summary card
                    if cachedTotalSpendThisMonth > 0 || monthlyBudget > 0 {
                        NavigationLink {
                            CostAnalyticsView()
                        } label: {
                            costSummaryRow
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                }

                // Recent activity
                if !cachedRecentJobs.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Recent Activity", systemImage: "clock.arrow.circlepath")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(spacing: 8) {
                            ForEach(cachedRecentJobs) { job in
                                recentJobRow(job: job)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                Spacer(minLength: 20)
            }
            .padding(.top)
        }
        .navigationTitle("Dashboard")
        .task {
            refreshCachedStats()
            refreshAllPrinters()
        }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
        }
        .refreshable {
            refreshCachedStats()
            refreshAllPrinters()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    // MARK: - Active Print Card

    @ViewBuilder
    private func activePrintCard(printer: Printer, state: PrinterLiveState) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "printer.fill")
                        .foregroundStyle(.blue)
                    Text(printer.name)
                        .font(.headline)
                    Spacer()
                    if let status = state.photonStatus {
                        StatusBadge(
                            text: status.displayText,
                            color: status == .printing ? .blue : .orange
                        )
                    }
                }

                if let fileName = state.fileName {
                    Text(fileName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let progress = state.progress {
                    VStack(spacing: 4) {
                        ProgressView(value: progress)
                            .tint(.blue)

                        HStack {
                            Text("\(Int(progress * 100))%")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.blue)

                            Spacer()

                            if let curr = state.currentLayer, let total = state.totalLayers {
                                Text("Layer \(curr)/\(total)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // ETA countdown
                    if let eta = state.estimatedCompletionDate {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.badge.checkmark")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text("ETA \(eta.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.green)
                            Spacer()
                            if let remaining = state.estimatedTimeRemaining, remaining > 0 {
                                Text(Self.formatCountdown(remaining))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .backgroundStyle(.fill.tertiary)
        .padding(.horizontal)
    }

    // MARK: - Printer Status Card

    @ViewBuilder
    private func printerStatusCard(printer: Printer) -> some View {
        let state = printerStates[printer.id]
        let isOnline = state?.isReachable == true

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(
                        isOnline
                            ? Color.green
                            : (state?.isReachable == nil ? Color.gray.opacity(0.4) : Color.red)
                    )
                    .frame(width: 10, height: 10)
                Spacer()
                Text(printer.printerProtocol.rawValue.uppercased())
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }

            Text(printer.name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)

            Text(printer.ipAddress)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let status = state?.photonStatus {
                Text(status.displayText)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(status.color)
            } else if isOnline {
                Text("Online")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if state?.isReachable == false {
                Text("Offline")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("Checking…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Quick Stat Card

    @ViewBuilder
    private func quickStatCard(title: String, value: String, icon: String, color: Color)
        -> some View
    {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Recent Job Row

    @ViewBuilder
    private func recentJobRow(job: PrintJob) -> some View {
        HStack(spacing: 10) {
            Image(systemName: job.status.icon)
                .foregroundStyle(job.status.color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.fileName ?? job.printerName)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(job.printerName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(job.startDate.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            StatusBadge(text: job.status.displayText, color: job.status.color, size: .small)
        }
        .padding(10)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Helpers

    /// Format a countdown duration into a compact string
    private static func formatCountdown(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 {
            return "\(h)h \(m)m left"
        }
        return "\(m)m left"
    }

    // MARK: - Cost Summary

    @AppStorage("resinCostPerMl") private var resinCostPerMl: Double = 0.0
    @AppStorage("resinCurrency") private var resinCurrency: String = "USD"
    @AppStorage("monthlyBudget") private var monthlyBudget: Double = 0.0

    private var totalSpendThisMonth: Double {
        cachedTotalSpendThisMonth
    }

    private var costCurrencySymbol: String {
        currencySymbol(for: resinCurrency)
    }

    @ViewBuilder
    private var costSummaryRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text(
                    "This Month: \(costCurrencySymbol)\(String(format: "%.2f", totalSpendThisMonth))"
                )
                .font(.subheadline)
                .fontWeight(.medium)
                if monthlyBudget > 0 {
                    let remaining = monthlyBudget - totalSpendThisMonth
                    Text(
                        remaining >= 0
                            ? "\(costCurrencySymbol)\(String(format: "%.2f", remaining)) remaining"
                            : "Over budget!"
                    )
                    .font(.caption)
                    .foregroundStyle(remaining >= 0 ? .green : .red)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var successRate: String {
        cachedSuccessRate
    }

    private func refreshAllPrinters() {
        refreshTask?.cancel()
        refreshTask = Task {
            await withTaskGroup(of: Void.self) { group in
                for printer in printers {
                    group.addTask { @MainActor in
                        await self.refreshSinglePrinter(printer)
                    }
                }
            }
        }
    }

    private func refreshSinglePrinter(_ printer: Printer) async {
        if printer.printerProtocol == .act {
            let service = PhotonPrinterService.shared
            if let status = try? await service.getStatus(
                ipAddress: printer.ipAddress,
                port: printer.port
            ) {
                var state = printerStates[printer.id] ?? PrinterLiveState()
                state.isReachable = true
                state.photonStatus = status
                printerStates[printer.id] = state
            } else {
                AppLogger.network.debug(
                    "Dashboard: ACT status check failed for \(printer.name)")
                var state = printerStates[printer.id] ?? PrinterLiveState()
                state.isReachable = false
                state.photonStatus = nil
                printerStates[printer.id] = state
            }
        } else {
            let api = AnycubicPrinterAPI.shared
            let reachable = await api.isReachable(ipAddress: printer.ipAddress, knownProtocol: printer.printerProtocol)
            var state = printerStates[printer.id] ?? PrinterLiveState()
            state.isReachable = reachable
            printerStates[printer.id] = state

            if reachable {
                if let job = try? await api.getJobStatus(
                    ipAddress: printer.ipAddress,
                    apiKey: printer.apiKey ?? ""
                ) {
                    var state = printerStates[printer.id] ?? PrinterLiveState()
                    state.fileName = job.job?.file?.name
                    state.progress = job.progress?.completion.map { $0 / 100.0 }
                    if let remaining = job.progress?.printTimeLeft, remaining > 0 {
                        state.estimatedTimeRemaining = remaining
                        state.estimatedCompletionDate = Date().addingTimeInterval(remaining)
                    }
                    printerStates[printer.id] = state
                }
            }
        }
    }
}
