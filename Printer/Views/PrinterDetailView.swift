//
//  PrinterDetailView.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import SwiftUI

/// Detailed view for a single printer with live status, system info, and print controls.
///
/// Uses `PrinterConnectionManager` for real-time polling and connection state tracking.
struct PrinterDetailView: View {
    @Bindable var printer: Printer
    @State private var manager = PrinterConnectionManager()
    @State private var controlError: String?
    @State private var showingControlError = false

    var body: some View {
        List {
            // Connection banner
            connectionBanner

            // Live status hero
            statusHeroSection

            // Current print progress (if printing)
            if let status = manager.photonStatus, status == .printing || status == .paused {
                printProgressSection
            } else if let job = manager.jobStatus,
                      job.state != "Operational" && job.state != "Closed" {
                httpPrintProgressSection(job: job)
            }

            // Print controls
            if manager.connectionState.isConnected {
                printControlsSection
            }

            // System information
            systemInfoSection

            // Connection details
            connectionDetailsSection
        }
        .navigationTitle(printer.name)
        .refreshable {
            await manager.refresh()
        }
        .onAppear {
            manager.startMonitoring(printer)
        }
        .onDisappear {
            manager.stopMonitoring()
        }
        .alert("Printer Error", isPresented: $showingControlError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(controlError ?? "An unknown error occurred.")
        }
    }

    // MARK: - Connection Banner

    @ViewBuilder
    private var connectionBanner: some View {
        Section {
            HStack(spacing: 12) {
                connectionIndicator

                VStack(alignment: .leading, spacing: 2) {
                    Text(connectionTitle)
                        .font(.headline)

                    Text(connectionSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if manager.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var connectionIndicator: some View {
        ZStack {
            Circle()
                .fill(connectionColor.opacity(0.2))
                .frame(width: 36, height: 36)

            Circle()
                .fill(connectionColor)
                .frame(width: 14, height: 14)

            if case .connecting = manager.connectionState {
                Circle()
                    .stroke(connectionColor.opacity(0.5), lineWidth: 2)
                    .frame(width: 28, height: 28)
                    .modifier(PulseAnimation())
            }
        }
    }

    private var connectionColor: Color {
        switch manager.connectionState {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .gray
        case .error: return .red
        }
    }

    private var connectionTitle: String {
        switch manager.connectionState {
        case .connected:
            return manager.photonStatus?.displayText ?? manager.printerStatus?.state.text ?? "Connected"
        case .connecting:
            return "Connecting…"
        case .disconnected:
            return "Offline"
        case .error:
            return "Connection Error"
        }
    }

    private var connectionSubtitle: String {
        switch manager.connectionState {
        case .connected:
            if let updated = manager.lastUpdated {
                return "Updated \(updated.formatted(.relative(presentation: .named)))"
            }
            return printer.ipAddress
        case .connecting:
            return "Attempting to reach \(printer.ipAddress)…"
        case .disconnected:
            return "Not connected"
        case .error(let msg):
            return msg
        }
    }

    // MARK: - Status Hero

    @ViewBuilder
    private var statusHeroSection: some View {
        Section("Status") {
            VStack(spacing: 16) {
                // Large status icon
                statusIcon
                    .frame(maxWidth: .infinity)

                // Status details row
                if manager.connectionState.isConnected {
                    statusDetailsRow
                }
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        let status = manager.photonStatus ?? statusFromPrinterStatus

        VStack(spacing: 8) {
            Image(systemName: iconName(for: status))
                .font(.system(size: 48))
                .foregroundStyle(iconColor(for: status).gradient)
                .symbolEffect(.pulse, options: .repeating, isActive: status == .printing)

            Text(status?.displayText ?? "Unknown")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(iconColor(for: status))
        }
    }

    @ViewBuilder
    private var statusDetailsRow: some View {
        HStack(spacing: 24) {
            if printer.printerProtocol == .act {
                statusDetail(
                    icon: "antenna.radiowaves.left.and.right",
                    label: "Protocol",
                    value: "ACT"
                )
            } else {
                statusDetail(
                    icon: "globe",
                    label: "Protocol",
                    value: printer.printerProtocol == .octoprint ? "OctoPrint" : "HTTP"
                )
            }

            if let temp = manager.printerStatus?.temperature {
                if let bed = temp.bed {
                    statusDetail(
                        icon: "thermometer.medium",
                        label: "Bed",
                        value: "\(Int(bed.actual))°C"
                    )
                }

                if let tool = temp.tool0 {
                    statusDetail(
                        icon: "flame",
                        label: "Nozzle",
                        value: "\(Int(tool.actual))°C"
                    )
                }
            }

            if let wifi = manager.wifiNetwork {
                statusDetail(
                    icon: "wifi",
                    label: "WiFi",
                    value: wifi
                )
            }
        }
    }

    @ViewBuilder
    private func statusDetail(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Print Progress (ACT)

    @ViewBuilder
    private var printProgressSection: some View {
        Section("Current Print") {
            if let status = manager.photonStatus {
                LabeledContent("State", value: status.displayText)
            }

            // ACT protocol doesn't provide progress percentage natively
            // but the status (printing/paused) is shown in the hero section
            if manager.photonStatus == .paused {
                Label("Print is paused — resume or cancel below", systemImage: "pause.circle")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Print Progress (HTTP)

    @ViewBuilder
    private func httpPrintProgressSection(job: PrintJobStatus) -> some View {
        Section("Current Print") {
            if let file = job.job?.file?.name {
                LabeledContent("File", value: file)
            }

            LabeledContent("State", value: job.state)

            if let progress = job.progress {
                if let completion = progress.completion {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: completion / 100.0)
                            .tint(progressColor(for: completion))

                        HStack {
                            Text("\(Int(completion))% complete")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            if let timeLeft = progress.printTimeLeft {
                                Text("\(formatDuration(timeLeft)) remaining")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let printTime = progress.printTime {
                    LabeledContent("Elapsed", value: formatDuration(printTime))
                }

                if let estimated = job.job?.estimatedPrintTime {
                    LabeledContent("Estimated Total", value: formatDuration(estimated))
                }
            }
        }
    }

    // MARK: - Print Controls

    @ViewBuilder
    private var printControlsSection: some View {
        let isPrinting = manager.photonStatus == .printing
            || manager.printerStatus?.state.flags.printing == true
        let isPaused = manager.photonStatus == .paused
            || manager.printerStatus?.state.flags.paused == true

        if isPrinting || isPaused {
            Section("Controls") {
                HStack(spacing: 16) {
                    Spacer()

                    if isPrinting {
                        Button {
                            performControl { try await manager.pausePrint() }
                        } label: {
                            Label("Pause", systemImage: "pause.circle.fill")
                                .font(.body)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }

                    if isPaused {
                        Button {
                            performControl { try await manager.resumePrint() }
                        } label: {
                            Label("Resume", systemImage: "play.circle.fill")
                                .font(.body)
                        }
                        .buttonStyle(.bordered)
                        .tint(.green)
                    }

                    Button(role: .destructive) {
                        performControl { try await manager.cancelPrint() }
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle.fill")
                            .font(.body)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - System Information

    @ViewBuilder
    private var systemInfoSection: some View {
        Section("Information") {
            LabeledContent("Name", value: printer.name)
            LabeledContent("IP Address", value: "\(printer.ipAddress):\(printer.port)")
            LabeledContent("Manufacturer", value: printer.manufacturer)

            if !printer.model.isEmpty {
                LabeledContent("Model", value: printer.model)
            }

            if let serial = printer.serialNumber {
                LabeledContent("Serial Number", value: serial)
            }

            if let firmware = printer.firmwareVersion {
                LabeledContent("Firmware", value: firmware)
            }

            if let sysInfo = manager.systemInfo {
                LabeledContent("Model Name", value: sysInfo.modelName)
            }

            protocolBadge
        }
    }

    @ViewBuilder
    private var protocolBadge: some View {
        LabeledContent("Protocol") {
            HStack(spacing: 4) {
                Image(systemName: protocolIcon)
                    .font(.caption)
                Text(protocolName)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.1))
            .clipShape(Capsule())
        }
    }

    private var protocolIcon: String {
        switch printer.printerProtocol {
        case .act: return "network"
        case .octoprint: return "globe"
        case .anycubicHTTP: return "antenna.radiowaves.left.and.right"
        }
    }

    private var protocolName: String {
        switch printer.printerProtocol {
        case .act: return "ACT (TCP \(printer.port))"
        case .octoprint: return "OctoPrint"
        case .anycubicHTTP: return "Anycubic HTTP"
        }
    }

    // MARK: - Connection Details

    @ViewBuilder
    private var connectionDetailsSection: some View {
        Section("Connection") {
            if let lastUpdated = manager.lastUpdated {
                LabeledContent("Last Updated") {
                    Text(lastUpdated.formatted(date: .omitted, time: .standard))
                }
            }

            if let lastConnected = printer.lastConnected {
                LabeledContent("Last Connected") {
                    Text(lastConnected.formatted(date: .abbreviated, time: .shortened))
                }
            }

            LabeledContent("Successful Polls", value: "\(manager.successfulPolls)")

            LabeledContent("Polling Interval") {
                Text("\(Int(manager.pollingInterval))s")
            }

            if manager.failedPolls > 0 {
                LabeledContent("Failed Polls") {
                    Text("\(manager.failedPolls)")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Helpers

    private func performControl(_ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
            } catch {
                await MainActor.run {
                    controlError = error.localizedDescription
                    showingControlError = true
                }
            }
        }
    }

    private var statusFromPrinterStatus: PhotonPrinterService.PhotonStatus? {
        guard let status = manager.printerStatus else { return nil }
        if status.state.flags.printing { return .printing }
        if status.state.flags.paused { return .paused }
        if status.state.flags.ready { return .idle }
        if status.state.flags.operational { return .idle }
        return .unknown(status.state.text)
    }

    private func iconName(for status: PhotonPrinterService.PhotonStatus?) -> String {
        switch status {
        case .idle: return "checkmark.circle"
        case .printing: return "printer.fill"
        case .paused: return "pause.circle"
        case .stopping: return "stop.circle"
        case .unknown: return "questionmark.circle"
        case .none: return "circle.dotted"
        }
    }

    private func iconColor(for status: PhotonPrinterService.PhotonStatus?) -> Color {
        switch status {
        case .idle: return .green
        case .printing: return .blue
        case .paused: return .orange
        case .stopping: return .red
        case .unknown: return .gray
        case .none: return .gray
        }
    }

    private func progressColor(for completion: Double) -> Color {
        switch completion {
        case 0..<25: return .red
        case 25..<50: return .orange
        case 50..<75: return .yellow
        default: return .green
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Pulse Animation

/// A pulsing ring animation for the connection indicator
struct PulseAnimation: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.0 : 1.0)
            .animation(
                .easeOut(duration: 1.2).repeatForever(autoreverses: false),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}
