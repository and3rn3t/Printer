//
//  CollectionManagementView.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import SwiftUI
import SwiftData

// MARK: - Collection List View

/// Sheet for browsing and managing model collections.
struct CollectionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ModelCollection.modifiedDate, order: .reverse) private var collections: [ModelCollection]

    @State private var showingNewCollection = false
    @State private var editingCollection: ModelCollection?

    var body: some View {
        NavigationStack {
            Group {
                if collections.isEmpty {
                    ContentUnavailableView(
                        "No Collections",
                        systemImage: "folder.badge.plus",
                        description: Text("Create collections to organize your models into groups")
                    )
                } else {
                    List {
                        ForEach(collections) { collection in
                            NavigationLink {
                                CollectionDetailView(collection: collection)
                            } label: {
                                collectionRow(collection)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    modelContext.delete(collection)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }

                                Button {
                                    editingCollection = collection
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Collections")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewCollection = true
                    } label: {
                        Label("New Collection", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewCollection) {
                NewCollectionView()
            }
            .sheet(item: $editingCollection) { collection in
                EditCollectionView(collection: collection)
            }
        }
    }

    @ViewBuilder
    private func collectionRow(_ collection: ModelCollection) -> some View {
        HStack(spacing: 12) {
            Image(systemName: collection.icon)
                .font(.title2)
                .foregroundStyle(Color(hex: collection.colorHex) ?? .blue)
                .frame(width: 36, height: 36)
                .background((Color(hex: collection.colorHex) ?? .blue).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(collection.name)
                    .font(.headline)
                Text("\(collection.models.count) model\(collection.models.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Collection Detail View

/// Shows all models in a collection with option to add/remove.
struct CollectionDetailView: View {
    @Bindable var collection: ModelCollection
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddModels = false

    var body: some View {
        Group {
            if collection.models.isEmpty {
                ContentUnavailableView(
                    "Empty Collection",
                    systemImage: "cube.transparent",
                    description: Text("Add models to this collection")
                )
            } else {
                List {
                    ForEach(collection.models) { model in
                        ModelRowView(model: model)
                    }
                    .onDelete(perform: removeModels)
                }
            }
        }
        .navigationTitle(collection.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddModels = true
                } label: {
                    Label("Add Models", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddModels) {
            AddModelsToCollectionView(collection: collection)
        }
    }

    private func removeModels(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                collection.models.remove(at: index)
            }
            collection.modifiedDate = Date()
        }
    }
}

// MARK: - New Collection View

/// Sheet for creating a new collection.
struct NewCollectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedIcon = "folder.fill"
    @State private var selectedColor = "007AFF"

    private let iconOptions = [
        "folder.fill", "star.fill", "heart.fill", "bookmark.fill",
        "tag.fill", "cube.fill", "paintbrush.fill", "wrench.fill",
        "gearshape.fill", "bolt.fill", "flame.fill", "leaf.fill"
    ]

    private let colorOptions = [
        "007AFF", "34C759", "FF3B30", "FF9500",
        "AF52DE", "FF2D55", "5856D6", "00C7BE"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Collection name", text: $name)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title3)
                                    .frame(width: 40, height: 40)
                                    .background(selectedIcon == icon ? (Color(hex: selectedColor) ?? .blue).opacity(0.2) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(selectedIcon == icon ? (Color(hex: selectedColor) ?? .blue) : .clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color(hex: selectedColor) ?? .blue)
                        }
                    }
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                        ForEach(colorOptions, id: \.self) { hex in
                            Button {
                                selectedColor = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex) ?? .blue)
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(.white, lineWidth: selectedColor == hex ? 3 : 0)
                                    )
                                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("New Collection")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let collection = ModelCollection(
                            name: name,
                            icon: selectedIcon,
                            colorHex: selectedColor
                        )
                        modelContext.insert(collection)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Edit Collection View

/// Sheet for editing an existing collection's name, icon, and color.
struct EditCollectionView: View {
    @Bindable var collection: ModelCollection
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var selectedIcon: String
    @State private var selectedColor: String

    private let iconOptions = [
        "folder.fill", "star.fill", "heart.fill", "bookmark.fill",
        "tag.fill", "cube.fill", "paintbrush.fill", "wrench.fill",
        "gearshape.fill", "bolt.fill", "flame.fill", "leaf.fill"
    ]

    private let colorOptions = [
        "007AFF", "34C759", "FF3B30", "FF9500",
        "AF52DE", "FF2D55", "5856D6", "00C7BE"
    ]

    init(collection: ModelCollection) {
        self.collection = collection
        _name = State(initialValue: collection.name)
        _selectedIcon = State(initialValue: collection.icon)
        _selectedColor = State(initialValue: collection.colorHex)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Collection name", text: $name)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title3)
                                    .frame(width: 40, height: 40)
                                    .background(selectedIcon == icon ? (Color(hex: selectedColor) ?? .blue).opacity(0.2) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(selectedIcon == icon ? (Color(hex: selectedColor) ?? .blue) : .clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color(hex: selectedColor) ?? .blue)
                        }
                    }
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                        ForEach(colorOptions, id: \.self) { hex in
                            Button {
                                selectedColor = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex) ?? .blue)
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(.white, lineWidth: selectedColor == hex ? 3 : 0)
                                    )
                                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Edit Collection")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        collection.name = name
                        collection.icon = selectedIcon
                        collection.colorHex = selectedColor
                        collection.modifiedDate = Date()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Add Models to Collection

/// Sheet for selecting models to add to a collection.
struct AddModelsToCollectionView: View {
    @Bindable var collection: ModelCollection
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PrintModel.modifiedDate, order: .reverse) private var allModels: [PrintModel]

    @State private var selectedIDs: Set<UUID> = []

    /// Models not already in this collection
    private var availableModels: [PrintModel] {
        let existingIDs = Set(collection.models.map(\.id))
        return allModels.filter { !existingIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if availableModels.isEmpty {
                    ContentUnavailableView(
                        "All Models Added",
                        systemImage: "checkmark.circle",
                        description: Text("Every model is already in this collection")
                    )
                } else {
                    List(availableModels, selection: $selectedIDs) { model in
                        ModelRowView(model: model)
                    }
                    #if os(iOS)
                    .environment(\.editMode, .constant(.active))
                    #endif
                }
            }
            .navigationTitle("Add Models")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selectedIDs.count))") {
                        let modelsToAdd = allModels.filter { selectedIDs.contains($0.id) }
                        for model in modelsToAdd {
                            collection.models.append(model)
                        }
                        collection.modifiedDate = Date()
                        dismiss()
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
        }
    }
}

// MARK: - Add to Collection Picker (from Model Detail)

/// Sheet shown from model detail to quickly add a model to one or more collections.
struct AddToCollectionPicker: View {
    let model: PrintModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ModelCollection.name) private var collections: [ModelCollection]

    @State private var showingNewCollection = false

    var body: some View {
        NavigationStack {
            Group {
                if collections.isEmpty {
                    ContentUnavailableView(
                        "No Collections",
                        systemImage: "folder.badge.plus",
                        description: Text("Create a collection first")
                    )
                } else {
                    List {
                        ForEach(collections) { collection in
                            let isInCollection = collection.models.contains(where: { $0.id == model.id })

                            Button {
                                withAnimation {
                                    if isInCollection {
                                        collection.models.removeAll { $0.id == model.id }
                                    } else {
                                        collection.models.append(model)
                                    }
                                    collection.modifiedDate = Date()
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: collection.icon)
                                        .foregroundStyle(Color(hex: collection.colorHex) ?? .blue)

                                    Text(collection.name)

                                    Spacer()

                                    if isInCollection {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Collections")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewCollection = true
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewCollection) {
                NewCollectionView()
            }
        }
    }
}

// MARK: - Color Extension

extension Color {
    /// Initialize a Color from a hex string (e.g. "007AFF")
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6 else { return nil }

        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
