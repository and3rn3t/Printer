//
//  InventoryView.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import SwiftUI
import SwiftData

/// Manage material inventory — bottles, spools, and stock levels.
struct InventoryView: View {
    @Query(sort: \InventoryItem.name) private var items: [InventoryItem]
    @Query(sort: \ResinProfile.name) private var profiles: [ResinProfile]
    @Environment(\.modelContext) private var modelContext

    @State private var showingAddItem = false

    /// Items that are low on stock
    private var lowStockItems: [InventoryItem] {
        items.filter { $0.isLowStock && !$0.isDepleted }
    }

    /// Active (non-depleted) items
    private var activeItems: [InventoryItem] {
        items.filter { !$0.isDepleted }
    }

    /// Depleted items
    private var depletedItems: [InventoryItem] {
        items.filter { $0.isDepleted }
    }

    var body: some View {
        List {
            // Low stock alerts
            if !lowStockItems.isEmpty {
                Section {
                    ForEach(lowStockItems) { item in
                        inventoryRow(item: item, showWarning: true)
                    }
                } header: {
                    Label("Low Stock", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            // Active items
            Section("In Stock (\(activeItems.count))") {
                if activeItems.isEmpty {
                    ContentUnavailableView(
                        "No Inventory",
                        systemImage: "shippingbox",
                        description: Text("Add resin bottles or filament spools to track your stock")
                    )
                } else {
                    ForEach(activeItems) { item in
                        NavigationLink {
                            InventoryItemDetailView(item: item)
                        } label: {
                            inventoryRow(item: item)
                        }
                    }
                    .onDelete(perform: deleteActiveItems)
                }
            }

            // Depleted items
            if !depletedItems.isEmpty {
                Section("Depleted (\(depletedItems.count))") {
                    ForEach(depletedItems) { item in
                        inventoryRow(item: item, showDepleted: true)
                    }
                    .onDelete(perform: deleteDepletedItems)
                }
            }
        }
        .navigationTitle("Inventory")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddItem = true
                } label: {
                    Label("Add Item", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddInventoryItemView(profiles: profiles)
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func inventoryRow(
        item: InventoryItem,
        showWarning: Bool = false,
        showDepleted: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            // Volume gauge
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                    .frame(width: 44, height: 44)

                Circle()
                    .trim(from: 0, to: 1.0 - item.usagePercentage)
                    .stroke(
                        gaugeColor(for: item),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(-90))

                Text("\(Int((1.0 - item.usagePercentage) * 100))")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(gaugeColor(for: item))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let profile = item.resinProfile {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color(hex: profile.colorHex) ?? .gray)
                                .frame(width: 8, height: 8)
                            Text(profile.name)
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }

                    if item.isExpired {
                        Text("EXPIRED")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.red)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.formattedRemaining)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(showWarning ? .orange : (showDepleted ? .red : .primary))

                Text("of \(Int(item.initialVolume)) \(item.resinProfile?.materialType.isResin == true ? "mL" : "g")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func gaugeColor(for item: InventoryItem) -> Color {
        if item.isDepleted { return .red }
        if item.isLowStock { return .orange }
        if item.usagePercentage > 0.7 { return .yellow }
        return .green
    }

    private func deleteActiveItems(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(activeItems[index])
        }
    }

    private func deleteDepletedItems(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(depletedItems[index])
        }
    }
}

// MARK: - Add Inventory Item View

struct AddInventoryItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let profiles: [ResinProfile]

    @State private var name = ""
    @State private var initialVolume: Double = 500
    @State private var selectedProfile: ResinProfile?
    @State private var purchaseCost: Double?
    @State private var purchaseDate = Date()
    @State private var expiryDate = Date().addingTimeInterval(365 * 24 * 3600)
    @State private var hasExpiry = false
    @State private var lowStockThreshold: Double = 50

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Elegoo Grey 500mL)", text: $name)

                    Picker("Material Profile", selection: $selectedProfile) {
                        Text("None").tag(nil as ResinProfile?)
                        ForEach(profiles) { profile in
                            HStack {
                                Circle()
                                    .fill(Color(hex: profile.colorHex) ?? .gray)
                                    .frame(width: 10, height: 10)
                                Text(profile.name)
                            }
                            .tag(profile as ResinProfile?)
                        }
                    }
                } header: {
                    Label("Details", systemImage: "info.circle")
                }

                Section {
                    HStack {
                        Text("Initial Volume")
                        Spacer()
                        TextField("500", value: $initialVolume, format: .number)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text(selectedProfile?.materialType.isResin == true ? "mL" : "g")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Low Stock Alert")
                        Spacer()
                        TextField("50", value: $lowStockThreshold, format: .number)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text(selectedProfile?.materialType.isResin == true ? "mL" : "g")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label("Volume", systemImage: "drop.fill")
                }

                Section {
                    DatePicker("Purchase Date", selection: $purchaseDate, displayedComponents: .date)

                    HStack {
                        Text("Cost")
                        Spacer()
                        TextField(
                            "0.00",
                            value: $purchaseCost,
                            format: .currency(code: UserDefaults.standard.string(forKey: "resinCurrency") ?? "USD")
                        )
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }

                    Toggle("Has Expiry Date", isOn: $hasExpiry)

                    if hasExpiry {
                        DatePicker("Expiry Date", selection: $expiryDate, displayedComponents: .date)
                    }
                } header: {
                    Label("Purchase", systemImage: "cart.fill")
                }
            }
            .navigationTitle("Add Inventory")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addItem()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || initialVolume <= 0)
                }
            }
        }
    }

    private func addItem() {
        let item = InventoryItem(
            name: name.trimmingCharacters(in: .whitespaces),
            initialVolume: initialVolume,
            resinProfile: selectedProfile,
            purchaseDate: purchaseDate,
            expiryDate: hasExpiry ? expiryDate : nil,
            purchaseCost: purchaseCost,
            lowStockThreshold: lowStockThreshold
        )
        modelContext.insert(item)
        dismiss()
    }
}

// MARK: - Inventory Item Detail View

struct InventoryItemDetailView: View {
    @Bindable var item: InventoryItem
    @State private var deductAmount: Double = 0
    @State private var showingManualDeduct = false

    var body: some View {
        List {
            // Volume gauge hero
            Section {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.15), lineWidth: 12)
                            .frame(width: 120, height: 120)

                        Circle()
                            .trim(from: 0, to: 1.0 - item.usagePercentage)
                            .stroke(
                                gaugeColor,
                                style: StrokeStyle(lineWidth: 12, lineCap: .round)
                            )
                            .frame(width: 120, height: 120)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.5), value: item.usagePercentage)

                        VStack(spacing: 2) {
                            Text("\(Int((1.0 - item.usagePercentage) * 100))%")
                                .font(.title)
                                .fontWeight(.bold)
                            Text("remaining")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 24) {
                        VStack {
                            Text(item.formattedRemaining)
                                .font(.headline)
                            Text("Remaining")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        VStack {
                            let unit = item.resinProfile?.materialType.isResin == true ? "mL" : "g"
                            Text(String(format: "%.0f %@", item.initialVolume, unit))
                                .font(.headline)
                            Text("Initial")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        VStack {
                            let usedUnit = item.resinProfile?.materialType.isResin == true ? "mL" : "g"
                            Text(String(format: "%.0f %@", item.initialVolume - item.remainingVolume, usedUnit))
                                .font(.headline)
                            Text("Used")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            // Details
            Section {
                if let profile = item.resinProfile {
                    LabeledContent {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(hex: profile.colorHex) ?? .gray)
                                .frame(width: 10, height: 10)
                            Text(profile.name)
                        }
                    } label: {
                        Label("Material", systemImage: profile.materialType.icon)
                    }
                }

                Toggle(isOn: $item.isOpened) {
                    Label("Opened", systemImage: "shippingbox")
                }

                if let date = item.purchaseDate {
                    LabeledContent {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                    } label: {
                        Label("Purchased", systemImage: "calendar")
                    }
                }

                if let cost = item.purchaseCost, cost > 0 {
                    let currencyCode = UserDefaults.standard.string(forKey: "resinCurrency") ?? "USD"
                    LabeledContent {
                        Text(cost, format: .currency(code: currencyCode))
                    } label: {
                        Label("Cost", systemImage: "dollarsign.circle")
                    }
                }

                if let expiry = item.expiryDate {
                    LabeledContent {
                        Text(expiry.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(item.isExpired ? .red : .primary)
                    } label: {
                        Label("Expires", systemImage: "calendar.badge.exclamationmark")
                    }
                }

                LabeledContent {
                    let unit = item.resinProfile?.materialType.isResin == true ? "mL" : "g"
                    Text(String(format: "%.0f %@", item.lowStockThreshold, unit))
                } label: {
                    Label("Low Stock Alert", systemImage: "exclamationmark.triangle")
                }
            } header: {
                Label("Details", systemImage: "info.circle")
            }

            // Manual deduction
            Section {
                Button {
                    showingManualDeduct = true
                } label: {
                    Label("Deduct Volume…", systemImage: "minus.circle.fill")
                }
                .disabled(item.isDepleted)
            } header: {
                Label("Manual Adjustment", systemImage: "slider.horizontal.3")
            }

            // Notes
            Section {
                TextEditor(text: $item.notes)
                    .frame(minHeight: 80)
            } header: {
                Label("Notes", systemImage: "note.text")
            }
        }
        .navigationTitle(item.name)
        .alert("Deduct Volume", isPresented: $showingManualDeduct) {
            TextField("Amount", value: $deductAmount, format: .number)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            Button("Deduct") {
                item.deduct(deductAmount)
                deductAmount = 0
            }
            Button("Cancel", role: .cancel) { deductAmount = 0 }
        } message: {
            Text("Enter the volume to deduct (in \(item.resinProfile?.materialType.isResin == true ? "mL" : "g")).")
        }
    }

    private var gaugeColor: Color {
        if item.isDepleted { return .red }
        if item.isLowStock { return .orange }
        if item.usagePercentage > 0.7 { return .yellow }
        return .green
    }
}
