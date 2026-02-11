//
//  PrintActivityAttributes.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import Foundation
import ActivityKit

/// Live Activity attributes for tracking an active print job
struct PrintActivityAttributes: ActivityAttributes {
    /// Static data set when the activity starts
    struct ContentState: Codable, Hashable {
        /// Progress from 0.0 to 1.0
        var progress: Double

        /// Current status description
        var status: String

        /// Elapsed time in seconds
        var elapsedSeconds: Int

        /// Estimated time remaining in seconds (nil if unknown)
        var estimatedSecondsRemaining: Int?

        /// Current layer / total layers (nil if unknown)
        var currentLayer: Int?
        var totalLayers: Int?
    }

    /// Name of the file being printed
    var fileName: String

    /// Name of the printer
    var printerName: String

    /// Printer protocol in use
    var printerProtocol: String
}
