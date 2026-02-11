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

// MARK: - Duration Formatting

/// Format a duration in seconds to a human-readable string
func formatDuration(_ seconds: Double) -> String {
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
