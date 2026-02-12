//
//  PrinterAPIModels.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import Foundation

// MARK: - API Response Models

/// Printer status from the API
nonisolated struct PrinterStatus: Codable, Sendable {
    let state: PrinterState
    let temperature: Temperature?
    let printerName: String?

    init(state: PrinterState, temperature: Temperature?, printerName: String? = nil) {
        self.state = state
        self.temperature = temperature
        self.printerName = printerName
    }

    enum CodingKeys: String, CodingKey {
        case state
        case temperature = "temperature"
        case printerName
    }
}

nonisolated struct PrinterState: Codable, Sendable {
    let text: String
    let flags: StateFlags
}

nonisolated struct StateFlags: Codable, Sendable {
    let operational: Bool
    let printing: Bool
    let paused: Bool
    let ready: Bool
}

nonisolated struct Temperature: Codable, Sendable {
    let bed: TemperatureData?
    let tool0: TemperatureData?
}

nonisolated struct TemperatureData: Codable, Sendable {
    let actual: Double
    let target: Double
}

/// Status of the current print job
nonisolated struct PrintJobStatus: Codable, Sendable {
    let job: JobInfo?
    let progress: ProgressInfo?
    let state: String

    struct JobInfo: Codable, Sendable {
        let file: JobFile?
        let estimatedPrintTime: Double?

        struct JobFile: Codable, Sendable {
            let name: String?
            let size: Int64?
        }
    }

    struct ProgressInfo: Codable, Sendable {
        let completion: Double?
        let printTime: Double?
        let printTimeLeft: Double?
    }
}

/// A file stored on the printer
nonisolated struct PrinterFile: Codable, Identifiable, Sendable {
    let name: String
    let size: Int64?
    let date: Date?

    var id: String { name }
}

/// Response wrapper for file list
nonisolated struct FileListResponse: Codable, Sendable {
    let files: [PrinterFile]
}

/// Response from file upload
nonisolated struct UploadResponse: Codable, Sendable {
    let files: FileInfo

    struct FileInfo: Codable, Sendable {
        let local: FileDetail

        struct FileDetail: Codable, Sendable {
            let name: String
            let origin: String
        }
    }
}
