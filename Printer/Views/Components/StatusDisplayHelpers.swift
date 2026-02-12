//
//  StatusDisplayHelpers.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import SwiftUI

// MARK: - PrintStatus Display Helpers

extension PrintStatus {
    /// SF Symbol name representing this status
    var icon: String {
        switch self {
        case .preparing: return "clock.fill"
        case .uploading: return "arrow.up.circle.fill"
        case .queued: return "tray.fill"
        case .printing: return "printer.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "xmark.circle"
        }
    }

    /// Color associated with this status
    var color: Color {
        switch self {
        case .preparing, .uploading, .queued: return .orange
        case .printing: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }

    /// Human-readable display text
    var displayText: String {
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

// MARK: - ModelSource Display Helpers

extension ModelSource {
    /// SF Symbol name representing this source
    var icon: String {
        switch self {
        case .scanned: return "camera.fill"
        case .imported: return "square.and.arrow.down.fill"
        case .downloaded: return "arrow.down.circle.fill"
        }
    }

    /// Human-readable display text
    var displayText: String {
        switch self {
        case .scanned: return "Scanned"
        case .imported: return "Imported"
        case .downloaded: return "Downloaded"
        }
    }
}

// MARK: - PrinterProtocol Display Helpers

extension PrinterProtocol {
    /// Human-readable display label
    var displayLabel: String {
        switch self {
        case .act: return "ACT"
        case .octoprint: return "OctoPrint"
        case .anycubicHTTP: return "HTTP"
        }
    }
}

// MARK: - PhotonStatus Display Helpers

extension PhotonPrinterService.PhotonStatus {
    /// Color associated with this printer status
    var color: Color {
        switch self {
        case .idle: return .green
        case .printing: return .blue
        case .paused: return .orange
        case .stopping: return .red
        case .unknown: return .gray
        }
    }

    /// SF Symbol name representing this printer status
    var icon: String {
        switch self {
        case .idle: return "checkmark.circle"
        case .printing: return "printer.fill"
        case .paused: return "pause.circle"
        case .stopping: return "stop.circle"
        case .unknown: return "questionmark.circle"
        }
    }
}

// MARK: - Duration Formatting

/// Format a duration in seconds to a human-readable string
nonisolated func formatDuration(_ seconds: Double) -> String {
    let totalSeconds = Int(seconds)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let secs = totalSeconds % 60
    if hours > 0 {
        return "\(hours)h \(minutes)m"
    } else if minutes > 0 {
        return "\(minutes)m \(secs)s"
    }
    return "\(secs)s"
}

// MARK: - Currency Formatting

/// Returns the display symbol for a currency code (e.g. "USD" → "$", "EUR" → "€")
func currencySymbol(for code: String) -> String {
    switch code {
    case "EUR": return "\u{20AC}"
    case "GBP": return "\u{00A3}"
    case "JPY": return "\u{00A5}"
    case "CAD": return "CA$"
    case "AUD": return "A$"
    default: return "$"
    }
}

/// Format a cost value with the appropriate currency symbol
func formatCost(_ value: Double, currency: String) -> String {
    "\(currencySymbol(for: currency))\(String(format: "%.2f", value))"
}

/// Format a cost value in short form (e.g. "$1k" for $1000)
func formatCostShort(_ value: Double, currency: String) -> String {
    if value >= 1000 {
        return "\(currencySymbol(for: currency))\(String(format: "%.0fk", value / 1000))"
    }
    return "\(currencySymbol(for: currency))\(String(format: "%.0f", value))"
}

// MARK: - IP Address Validation

/// Validate an IPv4 address string
func isValidIPAddress(_ address: String) -> Bool {
    let parts = address.split(separator: ".")
    guard parts.count == 4 else { return false }
    return parts.allSatisfy { part in
        guard let num = Int(part), num >= 0, num <= 255 else { return false }
        // Reject leading zeros (e.g., "01" or "001") unless it's just "0"
        return String(num) == String(part)
    }
}
