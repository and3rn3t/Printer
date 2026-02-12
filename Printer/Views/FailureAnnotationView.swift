//
//  FailureAnnotationView.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import SwiftUI

/// Sheet for annotating a failed print job with a structured failure reason and notes.
struct FailureAnnotationView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var job: PrintJob

    @State private var selectedReason: FailureReason?
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("What went wrong?") {
                    ForEach(FailureReason.allCases) { reason in
                        Button {
                            selectedReason = reason
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: reason.icon)
                                    .frame(width: 24)
                                    .foregroundStyle(selectedReason == reason ? .white : .red)

                                Text(reason.rawValue)
                                    .foregroundStyle(selectedReason == reason ? .white : .primary)

                                Spacer()

                                if selectedReason == reason {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(
                            selectedReason == reason ? Color.red.opacity(0.8) : Color.clear
                        )
                    }
                }

                Section("Notes (Optional)") {
                    TextField("What happened? Any details for next time...", text: $notes, axis: .vertical)
                        .lineLimit(4)
                }

                if let model = job.model {
                    Section("Job Info") {
                        LabeledContent("Model", value: model.name)
                        LabeledContent("Printer", value: job.printerName)
                        LabeledContent("Date", value: job.startDate.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }
            .navigationTitle("Annotate Failure")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(selectedReason == nil)
                }
            }
            .onAppear {
                selectedReason = job.failureReason
                notes = job.failureNotes ?? ""
            }
        }
    }

    private func save() {
        job.failureReason = selectedReason
        job.failureNotes = notes.isEmpty ? nil : notes
        dismiss()
    }
}
