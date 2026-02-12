//
//  PrinterStatusWidget.swift
//  PrinterWidget
//
//  Created by Matt on 2/11/26.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct PrinterStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> PrinterStatusEntry {
        PrinterStatusEntry(date: Date(), data: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (PrinterStatusEntry) -> Void) {
        let data = WidgetData.load() ?? .empty
        completion(PrinterStatusEntry(date: Date(), data: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PrinterStatusEntry>) -> Void) {
        let data = WidgetData.load() ?? .empty
        let entry = PrinterStatusEntry(date: Date(), data: data)
        // Refresh every 10 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 10, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Timeline Entry

struct PrinterStatusEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

// MARK: - Small Widget View

struct SmallPrinterWidget: View {
    let entry: PrinterStatusEntry

    var body: some View {
        if let printer = entry.data.printers.first {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Circle()
                        .fill(printer.isOnline ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(printer.name)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }

                Spacer()

                if printer.isPrinting, let progress = printer.progress {
                    VStack(alignment: .leading, spacing: 4) {
                        if let fileName = printer.fileName {
                            Text(fileName)
                                .font(.caption2)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }

                        ProgressView(value: progress)
                            .tint(.blue)

                        Text("\(Int(progress * 100))%")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.blue)
                    }
                } else {
                    Text(printer.statusText)
                        .font(.headline)
                        .foregroundStyle(printer.isOnline ? .green : .secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "printer.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("No Printers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Medium Widget View

struct MediumPrinterWidget: View {
    let entry: PrinterStatusEntry

    var body: some View {
        if entry.data.printers.isEmpty {
            HStack {
                Image(systemName: "printer.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text("Printer 3D")
                        .font(.headline)
                    Text("No printers configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        } else {
            HStack(spacing: 16) {
                // Active print or first printer status
                if let active = entry.data.printers.first(where: { $0.isPrinting }) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: "printer.fill")
                                .foregroundStyle(.blue)
                            Text(active.name)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                        }

                        if let fileName = active.fileName {
                            Text(fileName)
                                .font(.caption2)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }

                        if let progress = active.progress {
                            ProgressView(value: progress)
                                .tint(.blue)
                            Text("\(Int(progress * 100))%")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundStyle(.blue)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "printer.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        Text("All Idle")
                            .font(.headline)
                        Text("\(entry.data.printers.count) printer\(entry.data.printers.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Quick stats sidebar
                VStack(alignment: .trailing, spacing: 8) {
                    Label("\(entry.data.modelCount)", systemImage: "cube.transparent")
                        .font(.caption)

                    Label("\(entry.data.printJobCount)", systemImage: "clock.arrow.circlepath")
                        .font(.caption)

                    if entry.data.successRate > 0 {
                        Label("\(entry.data.successRate)%", systemImage: "checkmark.seal")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
    }
}

// MARK: - Widget Definition

struct PrinterStatusWidget: Widget {
    let kind = "PrinterStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PrinterStatusProvider()) { entry in
            SmallPrinterWidget(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Printer Status")
        .description("See your 3D printer status at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Accessory Widget (Lock Screen)

struct PrinterAccessoryProvider: TimelineProvider {
    func placeholder(in context: Context) -> PrinterStatusEntry {
        PrinterStatusEntry(date: Date(), data: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (PrinterStatusEntry) -> Void) {
        completion(PrinterStatusEntry(date: Date(), data: WidgetData.load() ?? .empty))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PrinterStatusEntry>) -> Void) {
        let data = WidgetData.load() ?? .empty
        let entry = PrinterStatusEntry(date: Date(), data: data)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 10, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct PrinterAccessoryWidget: Widget {
    let kind = "PrinterAccessoryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PrinterAccessoryProvider()) { entry in
            if let printer = entry.data.printers.first, printer.isPrinting, let progress = printer.progress {
                Gauge(value: progress) {
                    Image(systemName: "printer.fill")
                } currentValueLabel: {
                    Text("\(Int(progress * 100))%")
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .containerBackground(.fill.tertiary, for: .widget)
            } else {
                VStack(spacing: 2) {
                    Image(systemName: "printer.fill")
                        .font(.caption)
                    Text(entry.data.printers.first?.isOnline == true ? "Idle" : "Off")
                        .font(.caption2)
                }
                .containerBackground(.fill.tertiary, for: .widget)
            }
        }
        .configurationDisplayName("Printer")
        .description("Quick printer status on your Lock Screen.")
        .supportedFamilies([.accessoryCircular])
    }
}
