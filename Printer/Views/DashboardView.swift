//
//  DashboardView.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import SwiftUI
import SwiftData
import OSLog

/// Single-glance dashboard showing all printers' live status, active prints, and recent activity.
struct DashboardView: View {
    @Query private var printers: [Printer]
    @Query(sort: \PrintJob.startDate, order: .reverse) private var allJobs: [PrintJob]
    @Query(sort: \PrintModel.modifiedDate, order: .reverse) private var models: [PrintModel]

    @State private var printerStates: [UUID: PrinterLiveState] = [:]
    @State private var refreshTimer: Timer?
    @State private var errorMessage: String?
    @State private var showingError = false

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

    /// Recent completed/failed/cancelled jobs (last 5)
    private var recentJobs: [PrintJob] {
        allJobs
            .lazy
            .filter { $0.status == .completed || $0.status == .failed || $0.status == .cancelled }
            .prefix(5)
            .map { $0 }
    }

    /// Printers currently printing
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

    /// Maintenance alerts across all printers
    private var maintenanceAlerts: [MaintenanceScheduler.MaintenanceAlert] {
        MaintenanceScheduler.computeAlerts(printers: printers)
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
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ], spacing: 12) {
                            ForEach(printers) { printer in
                                printerStatusCard(printer: printer)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // Maintenance alerts
                if !maintenanceAlerts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Maintenance Due", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                            .padding(.horizontal)

                        VStack(spacing: 6) {
                            ForEach(maintenanceAlerts.prefix(3)) { alert in
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
                        .background(Color.orange.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                            value: "\(models.count)",
                            icon: "cube.transparent",
                            color: .blue
                        )
                        quickStatCard(
                            title: "Print Jobs",
                            value: "\(allJobs.count)",
                            icon: "printer.fill",
                            color: .green
                        )
                        quickStatCard(
                            title: "Success Rate",
                            value: successRate,
                            icon: "checkmark.seal.fill",
                            color: .purple
                        )
                    }
                    .padding(.horizontal)

                    // Cost summary card
                    if totalSpendThisMonth > 0 || monthlyBudget > 0 {
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
                if !recentJobs.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Recent Activity", systemImage: "clock.arrow.circlepath")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(spacing: 8) {
                            ForEach(recentJobs) { job in
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
        .onAppear { refreshAllPrinters() }
        .onDisappear { refreshTimer?.invalidate() }
        .refreshable { refreshAllPrinters() }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    // MARK: - Active Print Card

    @ViewBuilder
    private func activePrintCard(printer: Printer, state: PrinterLiveState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "printer.fill")
                    .foregroundStyle(.blue)
                Text(printer.name)
                    .font(.headline)
                Spacer()
                if let status = state.photonStatus {
                    Text(status.displayText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(status == .printing ? Color.blue.opacity(0.15) : Color.orange.opacity(0.15))
                        .foregroundStyle(status == .printing ? .blue : .orange)
                        .clipShape(Capsule())
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
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.background)
                .shadow(color: .blue.opacity(0.15), radius: 8, y: 4)
        }
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
                    .fill(isOnline ? Color.green : (state?.isReachable == nil ? Color.gray.opacity(0.4) : Color.red))
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
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.gray.opacity(0.1))
        }
    }

    // MARK: - Quick Stat Card

    @ViewBuilder
    private func quickStatCard(title: String, value: String, icon: String, color: Color) -> some View {
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
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.08))
        }
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

            Text(job.status.displayText)
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(job.status.color.opacity(0.12))
                .foregroundStyle(job.status.color)
                .clipShape(Capsule())
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.08))
        }
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
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        guard resinCostPerMl > 0 else { return 0 }
        return allJobs
            .filter { $0.status == .completed && $0.startDate >= start }
            .reduce(0) { sum, job in
                let vol = Double(job.model?.slicedVolumeMl ?? 0)
                return sum + vol * resinCostPerMl
            }
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
                Text("This Month: \(costCurrencySymbol)\(String(format: "%.2f", totalSpendThisMonth))")
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
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var successRate: String {
        let completed = allJobs.filter { $0.status == .completed }.count
        let total = allJobs.filter { $0.status == .completed || $0.status == .failed }.count
        guard total > 0 else { return "—" }
        return "\(Int(Double(completed) / Double(total) * 100))%"
    }

    private func refreshAllPrinters() {
        for printer in printers {
            Task {
                if printer.printerProtocol == .act {
                    let service = PhotonPrinterService.shared
                    if let status = try? await service.getStatus(
                        ipAddress: printer.ipAddress,
                        port: printer.port
                    ) {
                        await MainActor.run {
                            var state = printerStates[printer.id] ?? PrinterLiveState()
                            state.isReachable = true
                            state.photonStatus = status
                            printerStates[printer.id] = state
                        }
                    } else {
                        AppLogger.network.debug("Dashboard: ACT status check failed for \(printer.name)")
                        await MainActor.run {
                            var state = printerStates[printer.id] ?? PrinterLiveState()
                            state.isReachable = false
                            state.photonStatus = nil
                            printerStates[printer.id] = state
                        }
                    }
                } else {
                    let api = AnycubicPrinterAPI.shared
                    let reachable = await api.isReachable(ipAddress: printer.ipAddress)
                    await MainActor.run {
                        var state = printerStates[printer.id] ?? PrinterLiveState()
                        state.isReachable = reachable
                        printerStates[printer.id] = state
                    }

                    if reachable {
                        if let job = try? await api.getJobStatus(
                            ipAddress: printer.ipAddress,
                            apiKey: printer.apiKey ?? ""
                        ) {
                            await MainActor.run {
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
        }
    }
}
