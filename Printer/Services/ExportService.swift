//
//  ExportService.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Generates export files (CSV, PDF) for print data.
actor ExportService {

    // MARK: - CSV Export

    /// Export print jobs to CSV format.
    func exportJobsToCSV(jobs: [PrintJob]) -> String {
        var csv = "Date,Model,Printer,Status,Duration(s),File,Protocol,Failure Reason,Notes\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        for job in jobs {
            let date = dateFormatter.string(from: job.startDate)
            let model = escapeCSV(job.model?.name ?? "—")
            let printer = escapeCSV(job.printerName)
            let status = job.status.csvValue
            let duration = String(format: "%.0f", job.effectiveDuration)
            let file = escapeCSV(job.fileName ?? "—")
            let proto = escapeCSV(job.jobProtocol ?? "—")
            let failReason = escapeCSV(job.failureReason?.rawValue ?? "")
            let failNotes = escapeCSV(job.failureNotes ?? "")

            csv += "\(date),\(model),\(printer),\(status),\(duration),\(file),\(proto),\(failReason),\(failNotes)\n"
        }

        return csv
    }

    /// Export model library to CSV.
    func exportModelsToCSV(models: [PrintModel]) -> String {
        var csv = "Name,File Type,Size(bytes),Created,Modified,Prints,Favorite,Dimensions(mm)\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for model in models {
            let name = escapeCSV(model.name)
            let fileType = model.fileType.displayName
            let size = "\(model.fileSize)"
            let created = dateFormatter.string(from: model.createdDate)
            let modified = dateFormatter.string(from: model.modifiedDate)
            let prints = "\(model.printJobs.count)"
            let fav = model.isFavorite ? "Yes" : "No"

            var dims = "—"
            if let x = model.dimensionX, let y = model.dimensionY, let z = model.dimensionZ {
                dims = String(format: "%.1f×%.1f×%.1f", x, y, z)
            }

            csv += "\(name),\(fileType),\(size),\(created),\(modified),\(prints),\(fav),\(dims)\n"
        }

        return csv
    }

    // MARK: - Print Report (Plain Text)

    /// Generate a print report for a specific job.
    func generatePrintReport(job: PrintJob) -> String {
        var report = """
        ═══════════════════════════════════════
                    PRINT REPORT
        ═══════════════════════════════════════

        """

        report += "Model:      \(job.model?.name ?? job.fileName ?? "Unknown")\n"
        report += "Printer:    \(job.printerName)\n"
        report += "Status:     \(job.status.csvValue)\n"
        report += "Started:    \(job.startDate.formatted(date: .abbreviated, time: .shortened))\n"

        if let end = job.endDate {
            report += "Ended:      \(end.formatted(date: .abbreviated, time: .shortened))\n"
        }

        report += "Duration:   \(job.formattedDuration)\n"

        if let proto = job.jobProtocol {
            report += "Protocol:   \(proto)\n"
        }

        if let ip = job.printerIP {
            report += "Printer IP: \(ip)\n"
        }

        // Model details
        if let model = job.model {
            report += "\n─── Model Details ───\n"
            report += "File Type:  \(model.fileType.displayName)\n"
            report += "File Size:  \(ByteCountFormatter.string(fromByteCount: model.fileSize, countStyle: .file))\n"

            if let x = model.dimensionX, let y = model.dimensionY, let z = model.dimensionZ {
                report += "Dimensions: \(String(format: "%.1f × %.1f × %.1f mm", x, y, z))\n"
            }

            if let layers = model.slicedLayerCount {
                report += "Layers:     \(layers)\n"
            }

            if let volume = model.slicedVolumeMl {
                report += "Resin Vol:  \(String(format: "%.1f mL", volume))\n"
            }
        }

        // Failure info
        if job.status == .failed {
            report += "\n─── Failure Info ───\n"
            if let reason = job.failureReason {
                report += "Reason:     \(reason.rawValue)\n"
            }
            if let notes = job.failureNotes {
                report += "Notes:      \(notes)\n"
            }
        }

        // Material
        if let resin = job.resinProfile {
            report += "\n─── Material ───\n"
            report += "Profile:    \(resin.name)\n"
            if !resin.brand.isEmpty {
                report += "Brand:      \(resin.brand)\n"
            }
            report += "Type:       \(resin.materialType.rawValue)\n"
            if resin.costPerMl > 0 {
                report += "Cost/mL:    \(String(format: "%.3f", resin.costPerMl))\n"
            }
        }

        report += "\n═══════════════════════════════════════\n"
        report += "Generated by Printer · \(Date().formatted(date: .abbreviated, time: .shortened))\n"

        return report
    }

    // MARK: - Write to File

    /// Write string content to a temporary file and return the URL.
    func writeToTempFile(content: String, fileName: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}

// MARK: - PrintStatus CSV Extension

extension PrintStatus {
    var csvValue: String {
        switch self {
        case .preparing: return "Preparing"
        case .uploading: return "Uploading"
        case .queued: return "Queued"
        case .printing: return "Printing"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}
