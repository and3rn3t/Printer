//
//  AppLogger.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import OSLog

/// Centralized loggers for structured logging throughout the app.
///
/// Uses `os_log` subsystem/category pattern for efficient, filterable logging.
/// View logs in Console.app with: `subsystem:com.andernet.Printer`
enum AppLogger {
    /// General app lifecycle events (launch, background, widget updates)
    static let app = Logger(subsystem: "com.andernet.Printer", category: "App")

    /// Printer communication (ACT, OctoPrint, HTTP)
    static let network = Logger(subsystem: "com.andernet.Printer", category: "Network")

    /// SwiftData persistence operations
    static let data = Logger(subsystem: "com.andernet.Printer", category: "Data")

    /// Print job tracking and monitoring
    static let printJob = Logger(subsystem: "com.andernet.Printer", category: "PrintJob")

    /// File import, conversion, and mesh analysis
    static let fileOps = Logger(subsystem: "com.andernet.Printer", category: "FileOps")

    /// Printer discovery (Bonjour, ACT probing, subnet scanning)
    static let discovery = Logger(subsystem: "com.andernet.Printer", category: "Discovery")

    /// Background tasks and notifications
    static let background = Logger(subsystem: "com.andernet.Printer", category: "Background")

    /// iCloud sync operations
    static let sync = Logger(subsystem: "com.andernet.Printer", category: "Sync")
}
