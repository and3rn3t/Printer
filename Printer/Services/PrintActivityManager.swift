//
//  PrintActivityManager.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import Foundation
import OSLog
#if os(iOS)
import ActivityKit
#endif

/// Manages Live Activities for active print jobs
@MainActor
final class PrintActivityManager {
    static let shared = PrintActivityManager()

    #if os(iOS)
    private var currentActivity: Activity<PrintActivityAttributes>?
    #endif

    private init() {}

    // MARK: - Public API

    /// Start a Live Activity for a print job
    func startActivity(fileName: String, printerName: String, printerProtocol: String) {
        #if os(iOS)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = PrintActivityAttributes(
            fileName: fileName,
            printerName: printerName,
            printerProtocol: printerProtocol
        )

        let initialState = PrintActivityAttributes.ContentState(
            progress: 0.0,
            status: "Printing",
            elapsedSeconds: 0
        )

        do {
            let content = ActivityContent(state: initialState, staleDate: nil)
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            currentActivity = activity
        } catch {
            AppLogger.app.error("Failed to start Live Activity: \(error.localizedDescription)")
        }
        #endif
    }

    /// Update the Live Activity with new progress
    func updateActivity(
        progress: Double,
        status: String,
        elapsedSeconds: Int,
        estimatedSecondsRemaining: Int? = nil,
        currentLayer: Int? = nil,
        totalLayers: Int? = nil
    ) async {
        #if os(iOS)
        guard let activity = currentActivity else { return }

        let updatedState = PrintActivityAttributes.ContentState(
            progress: progress,
            status: status,
            elapsedSeconds: elapsedSeconds,
            estimatedSecondsRemaining: estimatedSecondsRemaining,
            currentLayer: currentLayer,
            totalLayers: totalLayers
        )

        let content = ActivityContent(state: updatedState, staleDate: nil)
        await activity.update(content)
        #endif
    }

    /// End the Live Activity
    func endActivity(finalStatus: String, progress: Double = 1.0) async {
        #if os(iOS)
        guard let activity = currentActivity else { return }

        let finalState = PrintActivityAttributes.ContentState(
            progress: progress,
            status: finalStatus,
            elapsedSeconds: 0
        )

        let content = ActivityContent(state: finalState, staleDate: nil)
        await activity.end(content, dismissalPolicy: .after(.now + 60))
        currentActivity = nil
        #endif
    }

    /// Whether a Live Activity is currently running
    var isActive: Bool {
        #if os(iOS)
        currentActivity != nil
        #else
        false
        #endif
    }
}
