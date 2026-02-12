//
//  PrinterConnectionManager.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import Foundation
import SwiftData
import ActivityKit
import OSLog

/// Manages live connection state and periodic status polling for a printer.
///
/// Uses `@Observable` so SwiftUI views react automatically to state changes.
/// For ACT protocol printers (Photon), polls via TCP. For HTTP printers, polls via REST.
@Observable
final class PrinterConnectionManager {

    // MARK: - Connection State

    /// The current connection state of the printer
    enum ConnectionState: Sendable {
        case disconnected
        case connecting
        case connected
        case error(String)

        var displayText: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting…"
            case .connected: return "Connected"
            case .error(let msg): return "Error: \(msg)"
            }
        }

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    // MARK: - Published State

    /// Current connection state
    private(set) var connectionState: ConnectionState = .disconnected

    /// Latest printer status from polling
    private(set) var printerStatus: PrinterStatus?

    /// Latest print job status (HTTP printers only)
    private(set) var jobStatus: PrintJobStatus?

    /// System information (ACT printers)
    private(set) var systemInfo: PhotonPrinterService.PhotonSystemInfo?

    /// WiFi network name (ACT printers)
    private(set) var wifiNetwork: String?

    /// Raw Photon status for ACT printers
    private(set) var photonStatus: PhotonPrinterService.PhotonStatus?

    /// Timestamp of last successful status update
    private(set) var lastUpdated: Date?

    /// Number of consecutive successful polls
    private(set) var successfulPolls: Int = 0

    /// Number of consecutive failed polls
    private(set) var failedPolls: Int = 0

    /// Whether a status refresh is currently in progress
    private(set) var isRefreshing: Bool = false

    /// Estimated print progress (0.0–1.0) for ACT printers based on elapsed time vs sliced metadata
    private(set) var estimatedProgress: Double?

    /// Estimated remaining time in seconds for ACT printers
    private(set) var estimatedTimeRemaining: Int?

    /// Whether the "finishing soon" notification has been sent for the current session
    private var finishingSoonNotified = false

    /// The polling interval in seconds
    var pollingInterval: TimeInterval = 5

    // MARK: - Print Session Tracking

    /// The currently active print job being tracked (auto-created on print start)
    private(set) var activeJob: PrintJob?

    /// Previous status used to detect transitions (e.g. idle → printing)
    private var previousPhotonStatus: PhotonPrinterService.PhotonStatus?

    /// Previous HTTP print state
    private var previousHTTPState: String?

    /// Timestamp when the current print session began (for elapsed time)
    private var printSessionStart: Date?

    /// The model context for creating/updating PrintJob records
    var modelContext: ModelContext?

    // MARK: - Private Properties

    private let api = AnycubicPrinterAPI.shared
    private let photonService = PhotonPrinterService.shared
    private var pollingTask: Task<Void, Never>?
    private var printer: Printer?

    // MARK: - Lifecycle

    /// Start monitoring a printer with periodic polling
    func startMonitoring(_ printer: Printer) {
        self.printer = printer
        stopMonitoring()
        AppLogger.network.info("Starting monitoring for \(printer.name) (\(printer.ipAddress), \(printer.printerProtocol.rawValue))")

        connectionState = .connecting

        pollingTask = Task { [weak self] in
            guard let self else { return }

            // Initial fetch — get system info once
            if printer.printerProtocol == .act {
                await self.fetchSystemInfo(printer)
            }

            // Polling loop
            while !Task.isCancelled {
                await self.refreshStatus(printer)

                do {
                    try await Task.sleep(for: .seconds(self.pollingInterval))
                } catch {
                    break
                }
            }
        }
    }

    /// Stop monitoring
    func stopMonitoring() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Manually trigger a single refresh
    func refresh() async {
        guard let printer else { return }
        await refreshStatus(printer)
    }

    // MARK: - Status Fetching

    private func refreshStatus(_ printer: Printer) async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            if printer.printerProtocol == .act {
                try await refreshACTStatus(printer)
            } else {
                try await refreshHTTPStatus(printer)
            }

            connectionState = .connected
            lastUpdated = Date()
            successfulPolls += 1
            failedPolls = 0

            // Update the printer model
            await MainActor.run {
                printer.isConnected = true
                printer.lastConnected = Date()
            }
        } catch {
            failedPolls += 1
            successfulPolls = 0
            let failCount = self.failedPolls
            AppLogger.network.warning("Status poll failed for \(printer.name) (attempt \(failCount)): \(error.localizedDescription)")

            if failedPolls >= 3 {
                connectionState = .error(error.localizedDescription)
                await MainActor.run {
                    printer.isConnected = false
                }
            } else if failedPolls == 1 {
                // First failure — show as connecting (retry)
                connectionState = .connecting
            }
        }
    }

    /// Fetch status from ACT protocol printer
    private func refreshACTStatus(_ printer: Printer) async throws {
        // getPrinterStatus internally calls getStatus + getSystemInfo,
        // so we only need this single call (no separate getStatus beforehand)
        let printerStat = try await photonService.getPrinterStatus(
            ipAddress: printer.ipAddress,
            port: printer.port
        )

        // Derive PhotonStatus from the combined result
        let status: PhotonPrinterService.PhotonStatus
        if printerStat.state.flags.printing {
            status = .printing
        } else if printerStat.state.flags.paused {
            status = .paused
        } else if printerStat.state.flags.ready || printerStat.state.flags.operational {
            status = .idle
        } else {
            status = .unknown(printerStat.state.text)
        }

        await MainActor.run {
            self.photonStatus = status
            self.printerStatus = printerStat

            // Detect print state transitions
            self.detectPrintTransition(newStatus: status)

            // Calculate estimated progress from elapsed time vs sliced metadata
            if status == .printing, let job = self.activeJob {
                let elapsed = job.effectiveDuration
                if let estimatedTotal = job.model?.slicedPrintTimeSeconds, estimatedTotal > 0 {
                    let totalSeconds = Double(estimatedTotal)
                    self.estimatedProgress = min(elapsed / totalSeconds, 0.99)
                    self.estimatedTimeRemaining = max(Int(totalSeconds - elapsed), 0)

                    // "Finishing soon" notification when < 10 minutes remain
                    if let remaining = self.estimatedTimeRemaining, remaining > 0, remaining < 600, !self.finishingSoonNotified {
                        self.finishingSoonNotified = true
                        PrintNotificationManager.shared.notifyPrintFinishingSoon(
                            fileName: job.fileName,
                            printerName: job.printerName,
                            estimatedTimeRemaining: TimeInterval(remaining)
                        )
                    }
                } else if elapsed > 0 {
                    // No metadata — show elapsed but no percentage
                    self.estimatedProgress = nil
                    self.estimatedTimeRemaining = nil
                }
            } else {
                self.estimatedProgress = nil
                self.estimatedTimeRemaining = nil
            }

            // Update Live Activity with current progress (ACT printers have limited progress info)
            #if os(iOS)
            if status == .printing {
                let elapsed = Int(self.activeJob?.effectiveDuration ?? 0)
                let progress = self.estimatedProgress ?? 0.0
                let remaining = self.estimatedTimeRemaining
                Task { @MainActor in
                    await PrintActivityManager.shared.updateActivity(
                        progress: progress,
                        status: "Printing",
                        elapsedSeconds: elapsed,
                        estimatedSecondsRemaining: remaining
                    )
                }
            }
            #endif

            // Update printer model with firmware if we have sysinfo
            if let sysInfo = self.systemInfo {
                printer.firmwareVersion = sysInfo.firmwareVersion
                printer.serialNumber = sysInfo.serialNumber
                if printer.model.isEmpty {
                    printer.model = sysInfo.modelName
                }
            }
        }
    }

    /// Fetch status from HTTP-based printer
    private func refreshHTTPStatus(_ printer: Printer) async throws {
        let status = try await api.getPrinterStatus(
            ipAddress: printer.ipAddress,
            apiKey: printer.apiKey,
            protocol: printer.printerProtocol
        )

        let job = try? await api.getJobStatus(
            ipAddress: printer.ipAddress,
            apiKey: printer.apiKey
        )

        await MainActor.run {
            self.printerStatus = status
            self.jobStatus = job

            // Detect HTTP print state transitions
            self.detectHTTPTransition(newState: status.state.text)

            // Update file name on active job from HTTP job info
            if let activeJob, let fileName = job?.job?.file?.name, activeJob.fileName == nil {
                activeJob.fileName = fileName
            }

            // Update Live Activity for HTTP printers
            #if os(iOS)
            if status.state.flags.printing, let jobInfo = job {
                let elapsed = Int(self.activeJob?.effectiveDuration ?? 0)
                let completionPct = jobInfo.progress?.completion ?? 0
                let progress = min(completionPct / 100.0, 1.0)
                let remaining = jobInfo.progress?.printTimeLeft.flatMap { Int($0) }
                Task { @MainActor in
                    await PrintActivityManager.shared.updateActivity(
                        progress: progress,
                        status: "Printing",
                        elapsedSeconds: elapsed,
                        estimatedSecondsRemaining: remaining
                    )
                }
            }
            #endif
        }
    }

    /// Fetch system info once on connect (ACT only)
    private func fetchSystemInfo(_ printer: Printer) async {
        do {
            let sysInfo = try await photonService.getSystemInfo(
                ipAddress: printer.ipAddress,
                port: printer.port
            )

            let wifi = try? await photonService.getWifiNetwork(
                ipAddress: printer.ipAddress,
                port: printer.port
            )

            await MainActor.run {
                self.systemInfo = sysInfo
                self.wifiNetwork = wifi

                // Populate printer model fields
                printer.firmwareVersion = sysInfo.firmwareVersion
                printer.serialNumber = sysInfo.serialNumber
                if printer.model.isEmpty {
                    printer.model = sysInfo.modelName
                }
            }
        } catch {
            AppLogger.network.warning("Failed to fetch sysinfo for \(printer.name): \(error.localizedDescription)")
            // Non-fatal — sysinfo is supplementary
        }
    }

    // MARK: - Print Controls

    /// Pause the current print
    func pausePrint() async throws {
        guard let printer else { return }
        try await api.pausePrint(
            ipAddress: printer.ipAddress,
            apiKey: printer.apiKey,
            protocol: printer.printerProtocol
        )
        await refresh()
    }

    /// Resume a paused print
    func resumePrint() async throws {
        guard let printer else { return }
        try await api.resumePrint(
            ipAddress: printer.ipAddress,
            apiKey: printer.apiKey,
            protocol: printer.printerProtocol
        )
        await refresh()
    }

    /// Cancel the current print
    func cancelPrint() async throws {
        guard let printer else { return }
        try await api.cancelPrint(
            ipAddress: printer.ipAddress,
            apiKey: printer.apiKey,
            protocol: printer.printerProtocol
        )
        await refresh()
    }

    // MARK: - Print Session Tracking

    /// Detect status transitions and manage PrintJob lifecycle
    private func detectPrintTransition(newStatus: PhotonPrinterService.PhotonStatus) {
        let old = previousPhotonStatus
        previousPhotonStatus = newStatus

        guard let printer else { return }

        switch (old, newStatus) {
        case (nil, .printing), (.idle, .printing), (.stopping, .printing):
            // Print started
            startPrintSession(printerName: printer.name, printerIP: printer.ipAddress, protocol: printer.printerProtocol)

        case (.printing, .paused):
            // Print paused — record elapsed so far
            recordElapsedTime()

        case (.paused, .printing):
            // Print resumed — restart the timer
            printSessionStart = Date()

        case (.printing, .idle), (.printing, .stopping),
             (.paused, .idle), (.paused, .stopping):
            // Print finished or was cancelled/stopped
            completePrintSession(status: (newStatus == .idle) ? .completed : .cancelled)

        default:
            break
        }
    }

    /// Detect HTTP print state transitions
    private func detectHTTPTransition(newState: String) {
        let old = previousHTTPState
        previousHTTPState = newState

        guard let printer else { return }

        if old != "Printing" && newState == "Printing" {
            startPrintSession(printerName: printer.name, printerIP: printer.ipAddress, protocol: printer.printerProtocol)
        } else if old == "Printing" && newState != "Printing" && newState != "Paused" && newState != "Pausing" {
            let finalStatus: PrintStatus = (newState == "Operational") ? .completed : .failed
            completePrintSession(status: finalStatus)
        }
    }

    /// Create a new PrintJob when a print starts
    private func startPrintSession(printerName: String, printerIP: String, protocol proto: PrinterProtocol) {
        printSessionStart = Date()
        AppLogger.printJob.info("Print session started on \(printerName) (\(proto.rawValue))")

        let job = PrintJob(
            printerName: printerName,
            status: .printing,
            printerIP: printerIP,
            jobProtocol: proto.rawValue
        )
        job.printStartDate = Date()

        // Try to get file name from HTTP job status
        if let fileName = jobStatus?.job?.file?.name {
            job.fileName = fileName
        }

        activeJob = job

        if let modelContext {
            Task { @MainActor in
                modelContext.insert(job)
            }
        }

        // Start Live Activity
        #if os(iOS)
        Task { @MainActor in
            PrintActivityManager.shared.startActivity(
                fileName: job.fileName ?? "Unknown",
                printerName: printerName,
                printerProtocol: proto.rawValue
            )
        }
        #endif

        // Start time-lapse capture for OctoPrint printers with webcam
        if proto == .octoprint, UserDefaults.standard.bool(forKey: "timelapseEnabled") != false {
            startTimelapseCapture(printerIP: printerIP, apiKey: printer?.apiKey, job: job)
        }
    }

    /// Record accumulated elapsed time (on pause)
    private func recordElapsedTime() {
        guard let start = printSessionStart else { return }
        let elapsed = Date().timeIntervalSince(start)

        if let job = activeJob {
            Task { @MainActor in
                job.elapsedTime += elapsed
            }
        }
        printSessionStart = nil
    }

    /// Finalize the active print session
    private func completePrintSession(status: PrintStatus) {
        AppLogger.printJob.info("Print session completed with status: \(status.csvValue)")

        // Add final elapsed time segment
        if let start = printSessionStart {
            let elapsed = Date().timeIntervalSince(start)
            if let job = activeJob {
                Task { @MainActor in
                    job.elapsedTime += elapsed
                    job.status = status
                    job.endDate = Date()

                    // Auto-deduct from inventory on successful completion
                    if status == .completed {
                        deductInventory(for: job)
                    }
                }
            }
        } else if let job = activeJob {
            Task { @MainActor in
                job.status = status
                job.endDate = Date()

                if status == .completed {
                    deductInventory(for: job)
                }
            }
        }

        // End Live Activity
        #if os(iOS)
        let finalStatus = status == .completed ? "Completed" : (status == .cancelled ? "Cancelled" : "Failed")
        let finalProgress = status == .completed ? 1.0 : 0.0
        Task { @MainActor in
            await PrintActivityManager.shared.endActivity(
                finalStatus: finalStatus,
                progress: finalProgress
            )
        }
        #endif

        // Local notification
        let notifFileName = activeJob?.fileName
        let notifPrinterName = activeJob?.printerName ?? "Printer"
        let notifDuration = activeJob?.effectiveDuration ?? 0
        let notifStatus = status == .completed ? "Completed" : (status == .cancelled ? "Cancelled" : "Failed")
        PrintNotificationManager.shared.notifyPrintFinished(
            fileName: notifFileName,
            printerName: notifPrinterName,
            status: notifStatus,
            duration: notifDuration
        )

        printSessionStart = nil
        activeJob = nil
        finishingSoonNotified = false

        // Stop time-lapse capture
        Task {
            await TimelapseCapture.shared.stopCapture()
        }
    }

    /// Start time-lapse snapshot capture for an OctoPrint print
    private func startTimelapseCapture(printerIP: String, apiKey: String?, job: PrintJob) {
        guard let context = modelContext else { return }
        let captureAPI = AnycubicPrinterAPI.shared

        Task {
            guard let snapshotURL = await captureAPI.getWebcamSnapshotURL(ipAddress: printerIP, apiKey: apiKey) else { return }
            await TimelapseCapture.shared.startCapture(snapshotURL: snapshotURL, job: job, modelContext: context)
        }
    }

    /// Deduct material volume from the first matching inventory item after a successful print
    @MainActor
    private func deductInventory(for job: PrintJob) {
        guard let volume = job.model?.slicedVolumeMl, volume > 0 else { return }
        guard let profile = job.resinProfile, let modelContext else { return }

        // Find an active (non-depleted) inventory item for this profile
        let descriptor = FetchDescriptor<InventoryItem>()
        guard let inventoryItems = try? modelContext.fetch(descriptor) else {
            AppLogger.data.warning("Failed to fetch inventory items for deduction")
            return
        }

        if let item = inventoryItems.first(where: { $0.resinProfile?.id == profile.id && !$0.isDepleted }) {
            item.deduct(Double(volume))

            // Send low-stock notification if needed
            if item.isLowStock {
                PrintNotificationManager.shared.notifyLowStock(
                    itemName: item.name,
                    remaining: item.remainingVolume,
                    unit: profile.materialType.isResin ? "mL" : "g"
                )
            }
        }
    }

    deinit {
        pollingTask?.cancel()
    }
}
