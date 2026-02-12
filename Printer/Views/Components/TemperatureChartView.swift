//
//  TemperatureChartView.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import SwiftUI
import Charts

/// A live temperature chart showing hotend and bed temps over time.
///
/// Displays the last 30 minutes of readings with current/target overlays.
/// Alerts when temperature deviates > 10°C from target.
struct TemperatureChartView: View {
    let readings: [TemperatureReading]
    let currentBedTemp: Double?
    let currentBedTarget: Double?
    let currentToolTemp: Double?
    let currentToolTarget: Double?

    /// Whether temperatures are deviating from targets
    private var bedDeviation: Bool {
        guard let actual = currentBedTemp, let target = currentBedTarget, target > 0 else { return false }
        return abs(actual - target) > 10
    }

    private var toolDeviation: Bool {
        guard let actual = currentToolTemp, let target = currentToolTarget, target > 0 else { return false }
        return abs(actual - target) > 10
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Current temps display
            HStack(spacing: 16) {
                if let temp = currentToolTemp {
                    tempBadge(
                        label: "Nozzle",
                        icon: "flame",
                        actual: temp,
                        target: currentToolTarget,
                        color: .orange,
                        isDeviating: toolDeviation
                    )
                }

                if let temp = currentBedTemp {
                    tempBadge(
                        label: "Bed",
                        icon: "square.3.layers.3d.down.left",
                        actual: temp,
                        target: currentBedTarget,
                        color: .blue,
                        isDeviating: bedDeviation
                    )
                }

                Spacer()
            }

            // Deviation warning
            if bedDeviation || toolDeviation {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Temperature deviation detected (> 10°C from target)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            // Chart
            if readings.count > 1 {
                Chart {
                    ForEach(readings.filter { $0.toolActual != nil }, id: \.timestamp) { reading in
                        LineMark(
                            x: .value("Time", reading.timestamp),
                            y: .value("Temp", reading.toolActual ?? 0)
                        )
                        .foregroundStyle(by: .value("Sensor", "Nozzle"))
                        .interpolationMethod(.catmullRom)
                    }

                    ForEach(readings.filter { $0.bedActual != nil }, id: \.timestamp) { reading in
                        LineMark(
                            x: .value("Time", reading.timestamp),
                            y: .value("Temp", reading.bedActual ?? 0)
                        )
                        .foregroundStyle(by: .value("Sensor", "Bed"))
                        .interpolationMethod(.catmullRom)
                    }

                    // Target lines
                    if let target = currentToolTarget, target > 0 {
                        RuleMark(y: .value("Nozzle Target", target))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                            .foregroundStyle(.orange.opacity(0.5))
                            .annotation(position: .top, alignment: .trailing) {
                                Text("Target \(Int(target))°")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                    }

                    if let target = currentBedTarget, target > 0 {
                        RuleMark(y: .value("Bed Target", target))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                            .foregroundStyle(.blue.opacity(0.5))
                    }
                }
                .chartForegroundStyleScale([
                    "Nozzle": Color.orange,
                    "Bed": Color.blue
                ])
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) {
                                Text("\(intValue)°")
                                    .font(.caption2)
                            }
                        }
                        AxisGridLine()
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date.formatted(.dateTime.hour().minute()))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 200)
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Collecting temperature data…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 200)
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func tempBadge(
        label: String,
        icon: String,
        actual: Double,
        target: Double?,
        color: Color,
        isDeviating: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(actual))°C")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(isDeviating ? .orange : .primary)

                if let target, target > 0 {
                    Text("/ \(Int(target))°C")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Temperature Reading

/// A single temperature reading at a point in time
struct TemperatureReading: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let toolActual: Double?
    let toolTarget: Double?
    let bedActual: Double?
    let bedTarget: Double?
}

// MARK: - Temperature History Manager

/// Keeps a ring buffer of temperature readings for the last 30 minutes.
@Observable
final class TemperatureHistoryManager {
    /// Maximum age for readings (30 minutes)
    private let maxAge: TimeInterval = 30 * 60

    /// All readings in chronological order
    private(set) var readings: [TemperatureReading] = []

    /// Add a new reading and prune old ones
    func addReading(_ reading: TemperatureReading) {
        readings.append(reading)
        pruneOldReadings()
    }

    /// Add a reading from raw temperature values
    func record(
        toolActual: Double?,
        toolTarget: Double?,
        bedActual: Double?,
        bedTarget: Double?
    ) {
        let reading = TemperatureReading(
            timestamp: Date(),
            toolActual: toolActual,
            toolTarget: toolTarget,
            bedActual: bedActual,
            bedTarget: bedTarget
        )
        addReading(reading)
    }

    /// Remove readings older than maxAge
    private func pruneOldReadings() {
        let cutoff = Date().addingTimeInterval(-maxAge)
        readings.removeAll { $0.timestamp < cutoff }
    }

    /// Clear all readings
    func reset() {
        readings.removeAll()
    }
}
