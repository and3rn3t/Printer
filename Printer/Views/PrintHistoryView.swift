//
//  PrintHistoryView.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import SwiftUI
import SwiftData

/// Browsable list of all print jobs across all printers.
///
/// Supports filtering by status and sorting by date. Shows duration, printer name,
/// file name, and status badges for each job.
struct PrintHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PrintJob.startDate, order: .reverse) private var allJobs: [PrintJob]

    @State private var statusFilter: StatusFilter = .all
    @State private var searchText = ""

    enum StatusFilter: String, CaseIterable {
        case all = "All"
        case active = "Active"
        case completed = "Completed"
        case failed = "Failed"

        var icon: String {
            switch self {
            case .all: return "list.bullet"
            case .active: return "printer.fill"
            case .completed: return "checkmark.circle"
            case .failed: return "xmark.circle"
            }
        }
    }

    var filteredJobs: [PrintJob] {
        var jobs = allJobs

        switch statusFilter {
        case .all:
            break
        case .active:
            jobs = jobs.filter {
                $0.status == .printing || $0.status == .uploading
                    || $0.status == .preparing || $0.status == .queued
            }
        case .completed:
            jobs = jobs.filter { $0.status == .completed }
        case .failed:
            jobs = jobs.filter { $0.status == .failed || $0.status == .cancelled }
        }

        if !searchText.isEmpty {
            jobs = jobs.filter {
                $0.printerName.localizedCaseInsensitiveContains(searchText)
                    || ($0.fileName ?? "").localizedCaseInsensitiveContains(searchText)
                    || ($0.model?.name ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }

        return jobs
    }

    var body: some View {
        Group {
            if allJobs.isEmpty {
                ContentUnavailableView(
                    "No Print History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Print jobs will appear here as you use your printers")
                )
            } else {
                List {
                    // Summary section
                    summarySection

                    // Jobs list
                    Section {
                        ForEach(filteredJobs) { job in
                            PrintHistoryRowView(job: job)
                        }
                        .onDelete(perform: deleteJobs)
                    } header: {
                        HStack {
                            Text("Jobs")
                            Spacer()
                            Text("\(filteredJobs.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Search by name, file, or printer")
            }
        }
        .navigationTitle("Print History")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(StatusFilter.allCases, id: \.self) { filter in
                        Button {
                            statusFilter = filter
                        } label: {
                            Label(filter.rawValue, systemImage: filter.icon)
                        }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }

    // MARK: - Summary

    @ViewBuilder
    private var summarySection: some View {
        Section {
            HStack(spacing: 0) {
                summaryStat(
                    value: "\(allJobs.count)",
                    label: "Total",
                    color: .blue
                )

                Divider()
                    .frame(height: 40)

                summaryStat(
                    value: "\(allJobs.filter { $0.status == .completed }.count)",
                    label: "Completed",
                    color: .green
                )

                Divider()
                    .frame(height: 40)

                summaryStat(
                    value: totalPrintTime,
                    label: "Print Time",
                    color: .purple
                )
            }
        }
    }

    @ViewBuilder
    private func summaryStat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var totalPrintTime: String {
        let total = allJobs.reduce(0.0) { $0 + $1.effectiveDuration }
        let hours = Int(total) / 3600
        let minutes = (Int(total) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    // MARK: - Actions

    private func deleteJobs(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(filteredJobs[index])
            }
        }
    }
}

// MARK: - Print History Row

struct PrintHistoryRowView: View {
    let job: PrintJob

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: statusIcon)
                    .font(.system(size: 16))
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                // Primary: model name or file name
                Text(job.model?.name ?? job.fileName ?? "Unknown File")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                // Secondary: printer + date
                HStack(spacing: 6) {
                    Image(systemName: "printer")
                        .font(.caption2)
                    Text(job.printerName)
                        .font(.caption)

                    Text("·")
                        .foregroundStyle(.tertiary)

                    Text(job.startDate.formatted(.relative(presentation: .named)))
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

                // Duration
                if job.effectiveDuration > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text(job.formattedDuration)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Status badge
            Text(statusText)
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.12))
                .foregroundStyle(statusColor)
                .clipShape(Capsule())
        }
        .padding(.vertical, 2)
    }

    // MARK: - Status Styling

    private var statusIcon: String {
        switch job.status {
        case .preparing: return "clock.fill"
        case .uploading: return "arrow.up.circle.fill"
        case .queued: return "tray.fill"
        case .printing: return "printer.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "xmark.circle"
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .preparing, .uploading, .queued: return .orange
        case .printing: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }

    private var statusText: String {
        switch job.status {
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
