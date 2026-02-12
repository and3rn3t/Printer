//
//  WidgetSharedData.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import Foundation

/// Shared printer state for WidgetKit home screen widgets.
///
/// Written by the main app via `UserDefaults(suiteName:)` and read by the widget extension.
/// Uses the app group identifier for cross-process data sharing.
struct WidgetPrinterState: Codable, Identifiable {
    let id: UUID
    let name: String
    let ipAddress: String
    let printerProtocol: String
    let isOnline: Bool
    let statusText: String
    let isPrinting: Bool
    let fileName: String?
    let progress: Double?
    let lastUpdated: Date
}

/// Collection of all printer states for widget display
struct WidgetData: Codable {
    let printers: [WidgetPrinterState]
    let modelCount: Int
    let printJobCount: Int
    let successRate: Int // 0-100

    /// UserDefaults key for shared widget data
    static let userDefaultsKey = "widgetPrinterData"

    /// App Group suite name — must match entitlements
    static let appGroupID = "group.com.printer3d.shared"

    /// Save to shared UserDefaults
    func save() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else { return }
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.userDefaultsKey)
        }
    }

    /// Load from shared UserDefaults
    static func load() -> Self? {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID),
              let data = defaults.data(forKey: userDefaultsKey),
              let state = try? JSONDecoder().decode(Self.self, from: data)
        else { return nil }
        return state
    }

    /// Empty state for when no data is available
    static let empty = Self(printers: [], modelCount: 0, printJobCount: 0, successRate: 0)
}
