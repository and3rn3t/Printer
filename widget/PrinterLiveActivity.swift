//
//  PrinterLiveActivity.swift
//  PrinterWidget
//
//  Created by Matt on 2/10/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct PrinterLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PrintActivityAttributes.self) { context in
            // Lock Screen / Banner UI
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded regions
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading) {
                        Image(systemName: "printer.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        Text(context.attributes.printerName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing) {
                        Text("\(Int(context.state.progress * 100))%")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.blue)
                        Text(context.state.status)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        Text(context.attributes.fileName)
                            .font(.headline)
                            .lineLimit(1)

                        ProgressView(value: context.state.progress)
                            .tint(.blue)

                        HStack {
                            if let current = context.state.currentLayer, let total = context.state.totalLayers {
                                Text("Layer \(current)/\(total)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(formattedTime(context.state.elapsedSeconds))
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            if let remaining = context.state.estimatedSecondsRemaining {
                                Text("• ~\(formattedTime(remaining)) left")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    EmptyView()
                }
            } compactLeading: {
                Image(systemName: "printer.fill")
                    .foregroundStyle(.blue)
            } compactTrailing: {
                Gauge(value: context.state.progress) {
                    Text("")
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(.blue)
                .scaleEffect(0.6)
            } minimal: {
                Gauge(value: context.state.progress) {
                    Image(systemName: "printer.fill")
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(.blue)
                .scaleEffect(0.6)
            }
        }
    }

    // MARK: - Lock Screen View

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<PrintActivityAttributes>) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "printer.fill")
                    .font(.headline)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.fileName)
                        .font(.headline)
                        .lineLimit(1)

                    Text(context.attributes.printerName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(Int(context.state.progress * 100))%")
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()
            }

            ProgressView(value: context.state.progress)
                .tint(.blue)

            HStack {
                Label(context.state.status, systemImage: statusIcon(context.state.status))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if let current = context.state.currentLayer, let total = context.state.totalLayers {
                    Text("Layer \(current)/\(total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(formattedTime(context.state.elapsedSeconds))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                if let remaining = context.state.estimatedSecondsRemaining {
                    Text("~\(formattedTime(remaining)) left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }

    // MARK: - Helpers

    private func statusIcon(_ status: String) -> String {
        switch status.lowercased() {
        case "printing": return "printer.fill"
        case "completed": return "checkmark.circle.fill"
        case "failed": return "xmark.circle.fill"
        case "paused": return "pause.circle.fill"
        default: return "clock.fill"
        }
    }

    private func formattedTime(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
