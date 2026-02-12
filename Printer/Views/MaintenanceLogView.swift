//
//  MaintenanceLogView.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import SwiftUI
import SwiftData

/// View for managing maintenance events for a specific printer.
struct MaintenanceLogView: View {
    @Environment(\.modelContext) private var modelContext
    let printer: Printer

    @Query(sort: \MaintenanceEvent.date, order: .reverse) private var allEvents: [MaintenanceEvent]
    @State private var showingAddEvent = false

    private var events: [MaintenanceEvent] {
        allEvents.filter { $0.printer?.id == printer.id }
    }

    private var overdueEvents: [MaintenanceEvent] {
        events.filter { $0.isOverdue }
    }

    private var upcomingEvents: [MaintenanceEvent] {
        events
            .filter { !$0.isOverdue && $0.nextDueDate != nil }
            .sorted { ($0.nextDueDate ?? .distantFuture) < ($1.nextDueDate ?? .distantFuture) }
    }

    var body: some View {
        List {
            // Overdue alerts
            if !overdueEvents.isEmpty {
                Section {
                    ForEach(overdueEvents) { event in
                        overdueRow(event)
                    }
                } header: {
                    Label("Overdue", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            // Upcoming maintenance
            if !upcomingEvents.isEmpty {
                Section("Upcoming") {
                    ForEach(upcomingEvents.prefix(5)) { event in
                        upcomingRow(event)
                    }
                }
            }

            // Full history
            Section("History") {
                if events.isEmpty {
                    ContentUnavailableView(
                        "No Maintenance Logged",
                        systemImage: "wrench.and.screwdriver",
                        description: Text("Tap + to log your first maintenance event")
                    )
                } else {
                    ForEach(events) { event in
                        eventRow(event)
                    }
                    .onDelete(perform: deleteEvents)
                }
            }
        }
        .navigationTitle("Maintenance")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddEvent = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddEvent) {
            AddMaintenanceEventView(printer: printer)
        }
    }

    // MARK: - Row Views

    private func overdueRow(_ event: MaintenanceEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: event.maintenanceType.icon)
                .foregroundStyle(.red)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.maintenanceType.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let days = event.daysUntilDue {
                    Text("\(abs(days)) days overdue")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private func upcomingRow(_ event: MaintenanceEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: event.maintenanceType.icon)
                .foregroundStyle(.orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.maintenanceType.rawValue)
                    .font(.subheadline)
                if let days = event.daysUntilDue {
                    Text("Due in \(days) days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let due = event.nextDueDate {
                Text(due, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func eventRow(_ event: MaintenanceEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: event.maintenanceType.icon)
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.maintenanceType.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if !event.notes.isEmpty {
                    Text(event.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(event.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let cost = event.cost, cost > 0 {
                    Text(cost, format: .currency(code: UserDefaults.standard.string(forKey: "resinCurrency") ?? "USD"))
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private func deleteEvents(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(events[index])
        }
    }
}

// MARK: - Add Maintenance Event

struct AddMaintenanceEventView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let printer: Printer

    @State private var selectedType: MaintenanceType = .vatCleaning
    @State private var date = Date()
    @State private var notes = ""
    @State private var cost: Double?
    @State private var reminderDays: Int = 0
    @State private var enableReminder = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Event Type") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(MaintenanceType.allCases) { type in
                            Label(type.rawValue, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                }

                Section("Details") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)

                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3)

                    HStack {
                        Text("Cost")
                        Spacer()
                        TextField("0.00", value: $cost, format: .number.precision(.fractionLength(2)))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                }

                Section("Reminder") {
                    Toggle("Set Reminder", isOn: $enableReminder)

                    if enableReminder {
                        Stepper("Every \(reminderDays) days", value: $reminderDays, in: 1...365)
                    }
                }
            }
            .navigationTitle("Log Maintenance")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveEvent() }
                }
            }
            .onChange(of: selectedType) { _, newType in
                if enableReminder {
                    reminderDays = newType.suggestedIntervalDays
                }
            }
            .onAppear {
                reminderDays = selectedType.suggestedIntervalDays
            }
        }
    }

    private func saveEvent() {
        let event = MaintenanceEvent(
            maintenanceType: selectedType,
            notes: notes,
            cost: cost,
            reminderIntervalDays: enableReminder ? reminderDays : 0
        )
        event.date = date
        event.printer = printer
        modelContext.insert(event)
        dismiss()
    }
}
