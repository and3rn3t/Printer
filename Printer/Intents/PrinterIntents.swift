//
//  PrinterIntents.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import AppIntents
import SwiftData

// MARK: - Check Printer Status

/// Siri / Shortcuts intent to check the status of a specific printer.
struct CheckPrinterStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Printer Status"
    static var description: IntentDescription = "Check the current status of a 3D printer."
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Printer")
    var printer: PrinterEntity

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let container = try ModelContainer(
            for: Printer.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: false)
        )
        let context = ModelContext(container)
        let allPrinters = try context.fetch(FetchDescriptor<Printer>())

        guard let target = allPrinters.first(where: { $0.id == printer.id }) else {
            return .result(value: "Printer not found", dialog: "I couldn't find that printer.")
        }

        switch target.printerProtocol {
        case .act:
            let service = PhotonPrinterService.shared
            do {
                let photonStatus = try await service.getStatus(ipAddress: target.ipAddress, port: target.port)
                let status = photonStatus.displayText
                return .result(value: status, dialog: "\(target.name) is \(status).")
            } catch {
                return .result(value: "Unreachable", dialog: "\(target.name) is not reachable.")
            }

        case .octoprint:
            let api = AnycubicPrinterAPI.shared
            let reachable = await api.isReachable(ipAddress: target.ipAddress)
            if reachable {
                if let job = try? await api.getJobStatus(ipAddress: target.ipAddress, apiKey: target.apiKey) {
                    let info = job.state + (job.progress?.completion.map { " (\(Int($0))%)" } ?? "")
                    return .result(value: info, dialog: "\(target.name): \(info)")
                }
                return .result(value: "Online", dialog: "\(target.name) is online.")
            } else {
                return .result(value: "Offline", dialog: "\(target.name) is offline.")
            }

        case .anycubicHTTP:
            return .result(value: "Online", dialog: "\(target.name) status checked.")
        }
    }
}

// MARK: - Get Print Progress

/// Siri / Shortcuts intent to check print progress on a specific printer.
struct GetPrintProgressIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Print Progress"
    static var description: IntentDescription = "Check the current print progress on a 3D printer."
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Printer")
    var printer: PrinterEntity

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let container = try ModelContainer(
            for: Printer.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: false)
        )
        let context = ModelContext(container)
        let allPrinters = try context.fetch(FetchDescriptor<Printer>())

        guard let target = allPrinters.first(where: { $0.id == printer.id }) else {
            return .result(value: "Printer not found", dialog: "I couldn't find that printer.")
        }

        switch target.printerProtocol {
        case .act:
            let service = PhotonPrinterService.shared
            do {
                let photonStatus = try await service.getStatus(ipAddress: target.ipAddress, port: target.port)
                let display = photonStatus.displayText
                return .result(value: display, dialog: "\(target.name): \(display)")
            } catch {
                return .result(value: "No active print", dialog: "\(target.name) is not reachable.")
            }

        case .octoprint:
            let api = AnycubicPrinterAPI.shared
            if let job = try? await api.getJobStatus(ipAddress: target.ipAddress, apiKey: target.apiKey) {
                let pct = job.progress?.completion.map { "\(Int($0))%" } ?? "unknown"
                let fileName = job.job?.file?.name ?? "Unknown file"
                let info = "\(fileName) — \(pct) complete"
                return .result(value: info, dialog: "\(target.name) progress: \(info)")
            }
            return .result(value: "No active print", dialog: "\(target.name) has no active print.")

        case .anycubicHTTP:
            return .result(value: "Unknown", dialog: "\(target.name) progress is not available via HTTP.")
        }
    }
}

// MARK: - Get Model Count

/// Siri / Shortcuts intent to check how many 3D models are in the library.
struct GetModelCountIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Model Count"
    static var description: IntentDescription = "Check how many 3D models are in your library."
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let container = try ModelContainer(
            for: PrintModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: false)
        )
        let context = ModelContext(container)
        let count = try context.fetchCount(FetchDescriptor<PrintModel>())
        let message = count == 1 ? "You have 1 model in your library." : "You have \(count) models in your library."
        return .result(value: count, dialog: "\(message)")
    }
}

// MARK: - Get Print Stats

/// Siri / Shortcuts intent to get print job statistics.
struct GetPrintStatsIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Print Stats"
    static var description: IntentDescription = "Get your 3D printing statistics including success rate."
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let container = try ModelContainer(
            for: PrintJob.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: false)
        )
        let context = ModelContext(container)
        let jobs = try context.fetch(FetchDescriptor<PrintJob>())

        let total = jobs.count
        let completed = jobs.filter { $0.status == .completed }.count
        let failed = jobs.filter { $0.status == .failed }.count
        let finished = completed + failed
        let successRate = finished > 0 ? Int(Double(completed) / Double(finished) * 100) : 0

        let summary = "\(total) jobs total, \(completed) completed, \(failed) failed (\(successRate)% success rate)"
        return .result(value: summary, dialog: "You have \(summary).")
    }
}

// MARK: - List Printers

/// Siri / Shortcuts intent to list all configured printers.
struct ListPrintersIntent: AppIntent {
    static var title: LocalizedStringResource = "List Printers"
    static var description: IntentDescription = "List all configured 3D printers."
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let container = try ModelContainer(
            for: Printer.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: false)
        )
        let context = ModelContext(container)
        let printers = try context.fetch(FetchDescriptor<Printer>())

        if printers.isEmpty {
            return .result(value: "No printers", dialog: "You haven't added any printers yet.")
        }

        let names = printers.map { "\($0.name) (\($0.ipAddress))" }.joined(separator: ", ")
        return .result(value: names, dialog: "Your printers: \(names)")
    }
}
