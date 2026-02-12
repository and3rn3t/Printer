//
//  ResinProfileView.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import SwiftData
import SwiftUI

/// List and manage resin / material profiles.
struct ResinProfileListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ResinProfile.name) private var profiles: [ResinProfile]
    @State private var showingAddProfile = false

    var body: some View {
        List {
            if profiles.isEmpty {
                ContentUnavailableView(
                    "No Material Profiles",
                    systemImage: "drop.fill",
                    description: Text(
                        "Add resin or filament profiles to track costs and exposure settings per material."
                    )
                )
            } else {
                ForEach(profiles) { profile in
                    NavigationLink {
                        ResinProfileDetailView(profile: profile)
                    } label: {
                        profileRow(profile)
                    }
                }
                .onDelete(perform: deleteProfiles)
            }
        }
        .navigationTitle("Material Profiles")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddProfile = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddProfile) {
            EditResinProfileView(profile: nil)
        }
    }

    private func profileRow(_ profile: ResinProfile) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: profile.colorHex) ?? .gray)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: profile.materialType.icon)
                        .font(.caption2)
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                HStack(spacing: 4) {
                    if !profile.brand.isEmpty {
                        Text(profile.brand)
                    }
                    Text("•")
                    Text(profile.materialType.rawValue)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if profile.costPerMl > 0 {
                let currencyCode = UserDefaults.standard.string(forKey: "resinCurrency") ?? "USD"
                Text(profile.costPerMl, format: .currency(code: currencyCode))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("/ mL")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func deleteProfiles(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(profiles[index])
        }
    }
}

// MARK: - Profile Detail View

struct ResinProfileDetailView: View {
    @Bindable var profile: ResinProfile
    @State private var showingEdit = false

    var body: some View {
        List {
            Section {
                HStack {
                    Circle()
                        .fill(Color(hex: profile.colorHex) ?? .gray)
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading) {
                        Text(profile.name)
                            .font(.headline)
                        if !profile.brand.isEmpty {
                            Text(profile.brand)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Material") {
                LabeledContent {
                    Text(profile.materialType.rawValue)
                } label: {
                    Label("Type", systemImage: profile.materialType.icon)
                }
                if !profile.color.isEmpty {
                    LabeledContent {
                        Text(profile.color)
                    } label: {
                        Label("Color", systemImage: "paintpalette.fill")
                    }
                }
                if profile.costPerMl > 0 {
                    LabeledContent {
                        let currencyCode =
                            UserDefaults.standard.string(forKey: "resinCurrency") ?? "USD"
                        Text(profile.costPerMl, format: .currency(code: currencyCode))
                    } label: {
                        Label("Cost / mL", systemImage: "dollarsign.circle")
                    }
                }
            }

            if profile.normalExposure != nil || profile.bottomExposure != nil
                || profile.bottomLayers != nil
            {
                Section {
                    if let exp = profile.normalExposure {
                        LabeledContent {
                            Text(String(format: "%.1fs", exp))
                        } label: {
                            Label("Normal Exposure", systemImage: "sun.max.fill")
                        }
                    }
                    if let bExp = profile.bottomExposure {
                        LabeledContent {
                            Text(String(format: "%.1fs", bExp))
                        } label: {
                            Label(
                                "Bottom Exposure",
                                systemImage: "sun.max.trianglebadge.exclamationmark")
                        }
                    }
                    if let bLayers = profile.bottomLayers {
                        LabeledContent {
                            Text("\(bLayers)")
                        } label: {
                            Label("Bottom Layers", systemImage: "square.stack.3d.up")
                        }
                    }
                    if let lh = profile.recommendedLayerHeight {
                        LabeledContent {
                            Text(String(format: "%.3f mm", lh))
                        } label: {
                            Label("Layer Height", systemImage: "ruler")
                        }
                    }
                } header: {
                    Label("Exposure Settings", systemImage: "sun.max.fill")
                }
            }

            if !profile.notes.isEmpty {
                Section {
                    Text(profile.notes)
                        .font(.subheadline)
                } header: {
                    Label("Notes", systemImage: "note.text")
                }
            }

            if !profile.printJobs.isEmpty {
                Section {
                    Label {
                        Text("\(profile.printJobs.count) print jobs used this material")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "printer.fill")
                            .foregroundStyle(.blue)
                    }
                } header: {
                    Label("Print History", systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .navigationTitle(profile.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEdit = true
                } label: {
                    Label("Edit", systemImage: "pencil.circle")
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            EditResinProfileView(profile: profile)
        }
    }
}

// MARK: - Edit / Add Profile

struct EditResinProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let profile: ResinProfile?

    @State private var name = ""
    @State private var brand = ""
    @State private var color = ""
    @State private var colorHex = "808080"
    @State private var costPerMl: Double = 0
    @State private var materialType: MaterialType = .standardResin
    @State private var normalExposure: Float?
    @State private var bottomExposure: Float?
    @State private var bottomLayers: Int?
    @State private var layerHeight: Float?
    @State private var notes = ""

    private var isEditing: Bool { profile != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Brand", text: $brand)
                    TextField("Color name", text: $color)

                    Picker("Material Type", selection: $materialType) {
                        ForEach(MaterialType.allCases) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }
                } header: {
                    Label("Basic Info", systemImage: "info.circle")
                }

                Section {
                    HStack {
                        Text("Cost / mL")
                        Spacer()
                        TextField(
                            "0.00", value: $costPerMl, format: .number.precision(.fractionLength(3))
                        )
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        #if os(iOS)
                            .keyboardType(.decimalPad)
                        #endif
                    }
                } header: {
                    Label("Cost", systemImage: "dollarsign.circle")
                }

                if materialType.isResin {
                    Section {
                        HStack {
                            Text("Normal Exposure (s)")
                            Spacer()
                            TextField(
                                "—",
                                value: $normalExposure,
                                format: .number.precision(.fractionLength(1))
                            )
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            #if os(iOS)
                                .keyboardType(.decimalPad)
                            #endif
                        }
                        HStack {
                            Text("Bottom Exposure (s)")
                            Spacer()
                            TextField(
                                "—",
                                value: $bottomExposure,
                                format: .number.precision(.fractionLength(1))
                            )
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            #if os(iOS)
                                .keyboardType(.decimalPad)
                            #endif
                        }
                        HStack {
                            Text("Bottom Layers")
                            Spacer()
                            TextField("—", value: $bottomLayers, format: .number)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                                #if os(iOS)
                                    .keyboardType(.numberPad)
                                #endif
                        }
                        HStack {
                            Text("Layer Height (mm)")
                            Spacer()
                            TextField(
                                "—",
                                value: $layerHeight,
                                format: .number.precision(.fractionLength(3))
                            )
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            #if os(iOS)
                                .keyboardType(.decimalPad)
                            #endif
                        }
                    } header: {
                        Label("Exposure Settings", systemImage: "sun.max.fill")
                    }
                }

                Section {
                    TextField("Wash & cure notes, etc.", text: $notes, axis: .vertical)
                        .lineLimit(4)
                } header: {
                    Label("Notes", systemImage: "note.text")
                }
            }
            .navigationTitle(isEditing ? "Edit Profile" : "New Profile")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { loadProfile() }
        }
    }

    private func loadProfile() {
        guard let p = profile else { return }
        name = p.name
        brand = p.brand
        color = p.color
        colorHex = p.colorHex
        costPerMl = p.costPerMl
        materialType = p.materialType
        normalExposure = p.normalExposure
        bottomExposure = p.bottomExposure
        bottomLayers = p.bottomLayers
        layerHeight = p.recommendedLayerHeight
        notes = p.notes
    }

    private func save() {
        if let p = profile {
            p.name = name
            p.brand = brand
            p.color = color
            p.colorHex = colorHex
            p.costPerMl = costPerMl
            p.materialType = materialType
            p.normalExposure = normalExposure
            p.bottomExposure = bottomExposure
            p.bottomLayers = bottomLayers
            p.recommendedLayerHeight = layerHeight
            p.notes = notes
        } else {
            let p = ResinProfile(
                name: name,
                brand: brand,
                color: color,
                colorHex: colorHex,
                costPerMl: costPerMl,
                materialType: materialType,
                notes: notes
            )
            p.normalExposure = normalExposure
            p.bottomExposure = bottomExposure
            p.bottomLayers = bottomLayers
            p.recommendedLayerHeight = layerHeight
            modelContext.insert(p)
        }
        dismiss()
    }
}
