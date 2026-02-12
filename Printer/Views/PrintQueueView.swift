//
//  PrintQueueView.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import SwiftUI
import SwiftData

// MARK: - Print Queue View

/// Displays and manages queued, active, and recent print jobs
struct PrintQueueView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PrintJob.startDate, order: .reverse) private var allJobs: [PrintJob]
    @Query private var printers: [Printer]

    // MARK: Computed Lists

    /// Jobs currently queued (waiting to print)
    private var queuedJobs: [PrintJob] {
        allJobs
            .filter { $0.status == .queued }
            .sorted { $0.queuePosition < $1.queuePosition }
    }

    /// Jobs currently printing or uploading
    private var activeJobs: [PrintJob] {
        allJobs.filter { $0.status == .printing || $0.status == .uploading || $0.status == .preparing }
    }

    /// Recently completed/failed/cancelled jobs
    private var recentJobs: [PrintJob] {
        allJobs.filter { $0.status == .completed || $0.status == .failed || $0.status == .cancelled }
            .prefix(10)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                // Active prints
                if !activeJobs.isEmpty {
                    Section {
                        ForEach(activeJobs) { job in
                            QueueJobRow(job: job)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        job.status = .cancelled
                                        job.endDate = Date()
                                    } label: {
                                        Label("Cancel", systemImage: "xmark.circle")
                                    }
                                }
                        }
                    } header: {
                        Label("Active", systemImage: "printer.fill")
                    }
                }

                // Queue
                Section {
                    if queuedJobs.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "tray")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text("Queue is empty")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 20)
                            Spacer()
                        }
                    } else {
                        ForEach(queuedJobs) { job in
                            QueueJobRow(job: job)
                        }
                        .onMove(perform: moveQueueItems)
                        .onDelete(perform: deleteQueueItems)
                    }
                } header: {
                    HStack {
                        Label("Queue", systemImage: "list.number")
                        Spacer()
                        if !queuedJobs.isEmpty {
                            Text("\(queuedJobs.count) job\(queuedJobs.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Recent
                if !recentJobs.isEmpty {
                    Section {
                        ForEach(recentJobs) { job in
                            QueueJobRow(job: job)
                                .swipeActions(edge: .trailing) {
                                    if job.status == .failed || job.status == .cancelled {
                                        Button {
                                            requeueJob(job)
                                        } label: {
                                            Label("Requeue", systemImage: "arrow.uturn.left.circle")
                                        }
                                        .tint(.blue)
                                    }
                                }
                        }
                    } header: {
                        Label("Recent", systemImage: "clock")
                    }
                }
            }
            .navigationTitle("Print Queue")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }

                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                #endif
            }
        }
    }

    // MARK: - Actions

    private func moveQueueItems(from source: IndexSet, to destination: Int) {
        var queued = queuedJobs
        queued.move(fromOffsets: source, toOffset: destination)
        for (index, job) in queued.enumerated() {
            job.queuePosition = index + 1
        }
    }

    private func deleteQueueItems(offsets: IndexSet) {
        for index in offsets {
            let job = queuedJobs[index]
            job.status = .cancelled
            job.endDate = Date()
            job.queuePosition = 0
        }
    }

    private func requeueJob(_ job: PrintJob) {
        let nextPosition = (queuedJobs.last?.queuePosition ?? 0) + 1
        job.status = .queued
        job.queuePosition = nextPosition
        job.endDate = nil
    }
}

// MARK: - Queue Job Row

struct QueueJobRow: View {
    let job: PrintJob

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 40, height: 40)

                if job.status == .printing || job.status == .uploading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: statusIcon)
                        .font(.subheadline)
                        .foregroundStyle(statusColor)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(job.fileName ?? "Unknown File")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(job.printerName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if job.queuePosition > 0 {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text("#\(job.queuePosition) in queue")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if job.effectiveDuration > 0 {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(job.formattedDuration)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Status badge
            Text(statusText)
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.15))
                .foregroundStyle(statusColor)
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String { job.status.icon }
    private var statusColor: Color { job.status.color }
    private var statusText: String { job.status.displayText }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: PrintModel.self, PrintJob.self, Printer.self, configurations: config
    )

    return PrintQueueView()
        .modelContainer(container)
}
