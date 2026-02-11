//
//  PrinterConnectionManager.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import Foundation

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

    /// The polling interval in seconds
    var pollingInterval: TimeInterval = 5

    // MARK: - Private Properties

    private let api = AnycubicPrinterAPI()
    private let photonService = PhotonPrinterService()
    private var pollingTask: Task<Void, Never>?
    private var printer: Printer?

    // MARK: - Lifecycle

    /// Start monitoring a printer with periodic polling
    func startMonitoring(_ printer: Printer) {
        self.printer = printer
        stopMonitoring()

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
        let status = try await photonService.getStatus(
            ipAddress: printer.ipAddress,
            port: printer.port
        )

        let printerStat = try await photonService.getPrinterStatus(
            ipAddress: printer.ipAddress,
            port: printer.port
        )

        await MainActor.run {
            self.photonStatus = status
            self.printerStatus = printerStat

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

    deinit {
        pollingTask?.cancel()
    }
}
