//
//  PhotoLogView.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import SwiftUI
import SwiftData
import OSLog

/// Displays the time-lapse photo log for a specific print job.
///
/// Shows a scrollable grid of captured snapshots with timestamps and progress.
/// Supports full-screen preview, deletion, and export.
struct PhotoLogView: View {
    let printJob: PrintJob

    @Environment(\.modelContext) private var modelContext
    @State private var snapshots: [PrintSnapshot] = []
    @State private var selectedSnapshot: PrintSnapshot?
    @State private var showingDeleteConfirmation = false

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 8)
    ]

    var body: some View {
        ScrollView {
            if snapshots.isEmpty {
                ContentUnavailableView(
                    "No Snapshots",
                    systemImage: "camera.metering.none",
                    description: Text("No time-lapse photos were captured for this print.")
                )
                .padding(.top, 60)
            } else {
                // Summary header
                VStack(spacing: 8) {
                    HStack {
                        Label("\(snapshots.count) snapshots", systemImage: "photo.stack")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let first = snapshots.first, let last = snapshots.last {
                            Text(timeSpanLabel(from: first.capturedAt, to: last.capturedAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 8)

                // Photo grid
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(snapshots) { snapshot in
                        SnapshotThumbnail(snapshot: snapshot)
                            .onTapGesture {
                                selectedSnapshot = snapshot
                            }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
        .navigationTitle("Time-lapse")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !snapshots.isEmpty {
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete All", systemImage: "trash")
                    }
                }
            }
        }
        .sheet(item: $selectedSnapshot) { snapshot in
            SnapshotDetailView(snapshot: snapshot)
        }
        .alert("Delete All Snapshots?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteAllSnapshots()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete all \(snapshots.count) time-lapse photos for this print.")
        }
        .onAppear {
            loadSnapshots()
        }
    }

    // MARK: - Data

    private func loadSnapshots() {
        let jobID = printJob.id
        let descriptor = FetchDescriptor<PrintSnapshot>(
            predicate: #Predicate { $0.printJob?.id == jobID },
            sortBy: [SortDescriptor(\PrintSnapshot.capturedAt)]
        )
        snapshots = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func deleteAllSnapshots() {
        for snapshot in snapshots {
            modelContext.delete(snapshot)
        }
        do {
            try modelContext.save()
        } catch {
            AppLogger.data.error("Failed to save after deleting snapshots: \(error.localizedDescription)")
        }
        snapshots.removeAll()
    }

    private func timeSpanLabel(from start: Date, to end: Date) -> String {
        let interval = end.timeIntervalSince(start)
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m span"
        } else {
            return "\(minutes)m span"
        }
    }
}

// MARK: - Snapshot Thumbnail

/// A single snapshot thumbnail in the photo grid.
private struct SnapshotThumbnail: View {
    let snapshot: PrintSnapshot

    var body: some View {
        VStack(spacing: 4) {
            if let image = imageFromData(snapshot.imageData) {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .bottomTrailing) {
                        Text("\(Int(snapshot.progressPercent))%")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.6))
                            .clipShape(Capsule())
                            .padding(4)
                    }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 100)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }

            Text(snapshot.capturedAt, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Full-Screen Detail

/// Full-screen snapshot viewer with metadata.
private struct SnapshotDetailView: View {
    let snapshot: PrintSnapshot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let image = imageFromData(snapshot.imageData) {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    ContentUnavailableView("Image Unavailable", systemImage: "photo")
                }

                HStack(spacing: 24) {
                    Label {
                        Text(snapshot.capturedAt, format: .dateTime.hour().minute().second())
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(.subheadline)

                    Label {
                        Text("\(Int(snapshot.progressPercent))% progress")
                    } icon: {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                    }
                    .font(.subheadline)

                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal)

                Spacer()
            }
            .padding()
            .navigationTitle("Snapshot")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Photo Log Badge

/// A small badge indicating how many time-lapse photos a job has.
struct PhotoLogBadge: View {
    let count: Int

    var body: some View {
        if !isEmpty {
            HStack(spacing: 3) {
                Image(systemName: "camera.fill")
                    .font(.caption2)
                Text("\(count)")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.blue)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.blue.opacity(0.12))
            .clipShape(Capsule())
        }
    }
}

// MARK: - Helpers

/// Cross-platform image loading from Data.
private func imageFromData(_ data: Data) -> Image? {
    #if canImport(UIKit)
    guard let uiImage = UIImage(data: data) else { return nil }
    return Image(uiImage: uiImage)
    #elseif canImport(AppKit)
    guard let nsImage = NSImage(data: data) else { return nil }
    return Image(nsImage: nsImage)
    #else
    return nil
    #endif
}
