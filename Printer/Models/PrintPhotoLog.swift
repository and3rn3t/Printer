//
//  PrintPhotoLog.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import Foundation
import SwiftData

/// A single timestamped snapshot captured during a print job.
///
/// Part of the time-lapse photo log feature. Images are stored
/// via `@Attribute(.externalStorage)` to keep the database lean.
@Model
final class PrintSnapshot {
    @Attribute(.unique) var id: UUID

    /// JPEG image data for the snapshot
    @Attribute(.externalStorage) var imageData: Data

    /// When this snapshot was captured
    var capturedAt: Date

    /// Progress percentage at time of capture (0–100)
    var progressPercent: Double

    /// The print job this snapshot belongs to
    var printJob: PrintJob?

    init(imageData: Data, progressPercent: Double, printJob: PrintJob? = nil) {
        self.id = UUID()
        self.imageData = imageData
        self.capturedAt = Date()
        self.progressPercent = progressPercent
        self.printJob = printJob
    }
}
