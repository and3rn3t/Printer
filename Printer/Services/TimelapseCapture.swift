//
//  TimelapseCapture.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Captures periodic webcam snapshots during active prints for building time-lapse photo logs.
///
/// Works with OctoPrint printers that expose a webcam snapshot URL.
/// Capture interval is configurable via UserDefaults ("timelapseIntervalSeconds").
actor TimelapseCapture {
    static let shared = TimelapseCapture()

    /// Whether capture is currently active
    private(set) var isCapturing = false

    /// The URL session used for fetching snapshots
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    /// Active capture task
    private var captureTask: Task<Void, Never>?

    /// Snapshot URL for current print
    private var snapshotURL: URL?

    /// Model context for persisting snapshots
    private var modelContext: ModelContext?

    /// The active print job
    private var activeJob: PrintJob?

    /// Number of snapshots captured in current session
    private(set) var snapshotCount: Int = 0

    /// Capture interval from settings (default 60 seconds)
    private var captureInterval: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: "timelapseIntervalSeconds")
        return stored > 0 ? stored : 60
    }

    // MARK: - Public API

    /// Start capturing snapshots for a print job.
    ///
    /// - Parameters:
    ///   - snapshotURL: URL to fetch JPEG snapshots from (e.g., OctoPrint webcam)
    ///   - job: The active PrintJob to associate snapshots with
    ///   - modelContext: SwiftData context for persisting snapshots
    func startCapture(snapshotURL: URL, job: PrintJob, modelContext: ModelContext) {
        guard !isCapturing else { return }

        self.snapshotURL = snapshotURL
        self.activeJob = job
        self.modelContext = modelContext
        self.snapshotCount = 0
        self.isCapturing = true

        captureTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                await self.captureSnapshot()

                do {
                    try await Task.sleep(for: .seconds(self.captureInterval))
                } catch {
                    break
                }
            }
        }
    }

    /// Stop capturing and clean up.
    func stopCapture() {
        captureTask?.cancel()
        captureTask = nil
        isCapturing = false
        snapshotURL = nil
        activeJob = nil
        modelContext = nil
        snapshotCount = 0
    }

    /// Capture a single snapshot on demand (for manual trigger).
    func captureOnDemand() async {
        guard isCapturing else { return }
        await captureSnapshot()
    }

    // MARK: - Private

    private func captureSnapshot() async {
        guard let url = snapshotURL, let job = activeJob, let context = modelContext else { return }

        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  !data.isEmpty else { return }

            // Verify it's actually image data (JPEG starts with FF D8)
            guard data.count > 2, data[0] == 0xFF, data[1] == 0xD8 else { return }

            // Compress to reduce storage (resize to max 640px wide)
            let imageData = compressSnapshot(data)

            let progress = job.effectiveDuration > 0 ? min(100, (job.effectiveDuration / max(1, job.elapsedTime)) * 100) : 0

            await MainActor.run {
                let snapshot = PrintSnapshot(
                    imageData: imageData,
                    progressPercent: progress,
                    printJob: job
                )
                context.insert(snapshot)
                try? context.save()
            }

            snapshotCount += 1
        } catch {
            // Silently skip failed captures — network glitch, printer busy, etc.
        }
    }

    /// Compress JPEG data to reduce storage footprint.
    private func compressSnapshot(_ data: Data) -> Data {
        #if canImport(UIKit)
        if let image = UIImage(data: data) {
            let maxWidth: CGFloat = 640
            if image.size.width > maxWidth {
                let scale = maxWidth / image.size.width
                let newSize = CGSize(width: maxWidth, height: image.size.height * scale)
                let renderer = UIGraphicsImageRenderer(size: newSize)
                let resized = renderer.jpegData(withCompressionQuality: 0.7) { ctx in
                    image.draw(in: CGRect(origin: .zero, size: newSize))
                }
                return resized
            }
            return image.jpegData(compressionQuality: 0.7) ?? data
        }
        #endif
        return data
    }
}
