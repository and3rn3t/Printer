//
//  TagBrowserView.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import SwiftUI
import SwiftData

/// Tag cloud browser showing all tags across the model library with counts.
///
/// Tap a tag to filter the library. Supports creating and managing saved filter presets.
struct TagBrowserView: View {
    @Query(sort: \PrintModel.modifiedDate, order: .reverse) private var models: [PrintModel]
    @Query(sort: \SavedFilter.name) private var savedFilters: [SavedFilter]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTags: Set<String> = []
    @State private var searchText = ""
    @State private var showingSaveFilter = false
    @State private var newFilterName = ""

    /// All unique tags across all models with their counts
    private var tagCounts: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for model in models {
            for tag in model.tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts
            .map { (tag: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    /// Tags matching the search text
    private var filteredTags: [(tag: String, count: Int)] {
        if searchText.isEmpty { return tagCounts }
        return tagCounts.filter { $0.tag.localizedCaseInsensitiveContains(searchText) }
    }

    /// Models matching the selected tags
    private var filteredModels: [PrintModel] {
        guard !selectedTags.isEmpty else { return [] }
        return models.filter { model in
            let modelTags = Set(model.tags.map { $0.lowercased() })
            let filterTags = Set(selectedTags.map { $0.lowercased() })
            return filterTags.isSubset(of: modelTags)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // Saved filters section
                if !savedFilters.isEmpty {
                    Section("Saved Filters") {
                        ForEach(savedFilters) { filter in
                            NavigationLink {
                                SavedFilterResultsView(filter: filter)
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(filter.name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        HStack(spacing: 6) {
                                            if !filter.tags.isEmpty {
                                                Text(filter.tags.joined(separator: ", "))
                                                    .font(.caption2)
                                                    .foregroundStyle(.blue)
                                            }
                                            if filter.favoritesOnly {
                                                Image(systemName: "star.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.yellow)
                                            }
                                            if filter.printReadyOnly {
                                                Text("Print Ready")
                                                    .font(.caption2)
                                                    .foregroundStyle(.green)
                                            }
                                        }
                                    }
                                } icon: {
                                    Image(systemName: filter.icon)
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .onDelete(perform: deleteSavedFilters)
                    }
                }

                // Tag cloud section
                if tagCounts.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No Tags",
                            systemImage: "tag.slash",
                            description: Text("Add tags to models in the model detail view")
                        )
                    }
                } else {
                    Section("Tags (\(tagCounts.count))") {
                        FlowLayout(spacing: 8) {
                            ForEach(filteredTags, id: \.tag) { item in
                                tagChip(tag: item.tag, count: item.count)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Filtered results
                if !selectedTags.isEmpty {
                    Section("Matching Models (\(filteredModels.count))") {
                        if filteredModels.isEmpty {
                            Text("No models match the selected tags")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(filteredModels) { model in
                                HStack {
                                    if let data = model.thumbnailData {
                                        #if os(macOS)
                                        if let nsImage = NSImage(data: data) {
                                            Image(nsImage: nsImage)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 40, height: 40)
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                        }
                                        #else
                                        if let uiImage = UIImage(data: data) {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 40, height: 40)
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                        }
                                        #endif
                                    } else {
                                        Image(systemName: "cube.transparent")
                                            .frame(width: 40, height: 40)
                                            .foregroundStyle(.blue)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.name)
                                            .font(.subheadline)
                                            .lineLimit(1)
                                        Text(model.fileType.displayName)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Text(ByteCountFormatter.string(fromByteCount: model.fileSize, countStyle: .file))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search tags")
            .navigationTitle("Tags & Filters")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }

                if !selectedTags.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingSaveFilter = true
                        } label: {
                            Label("Save Filter", systemImage: "square.and.arrow.down")
                        }
                    }

                    ToolbarItem(placement: .secondaryAction) {
                        Button("Clear Selection") {
                            selectedTags.removeAll()
                        }
                    }
                }
            }
            .alert("Save Filter", isPresented: $showingSaveFilter) {
                TextField("Filter name", text: $newFilterName)
                Button("Save") {
                    saveCurrentFilter()
                }
                Button("Cancel", role: .cancel) { newFilterName = "" }
            } message: {
                Text("Save the current tag selection as a reusable filter.")
            }
        }
    }

    // MARK: - Tag Chip

    @ViewBuilder
    private func tagChip(tag: String, count: Int) -> some View {
        let isSelected = selectedTags.contains(tag)
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isSelected {
                    selectedTags.remove(tag)
                } else {
                    selectedTags.insert(tag)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(tag)
                    .font(.caption)
                    .fontWeight(.medium)
                Text("\(count)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(isSelected ? Color.white.opacity(0.3) : Color.blue.opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                Capsule().fill(isSelected ? AnyShapeStyle(Color.blue) : AnyShapeStyle(.fill.tertiary))
            }
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func saveCurrentFilter() {
        let name = newFilterName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let filter = SavedFilter(
            name: name,
            tags: Array(selectedTags)
        )
        modelContext.insert(filter)
        newFilterName = ""
    }

    private func deleteSavedFilters(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(savedFilters[index])
        }
    }
}

// MARK: - Saved Filter Results View

/// Shows models matching a saved filter
struct SavedFilterResultsView: View {
    let filter: SavedFilter
    @Query(sort: \PrintModel.modifiedDate, order: .reverse) private var models: [PrintModel]

    private var matchingModels: [PrintModel] {
        models.filter { filter.matches($0) }
    }

    var body: some View {
        List {
            Section {
                if !filter.tags.isEmpty {
                    LabeledContent("Tags", value: filter.tags.joined(separator: ", "))
                }
                if let fileType = filter.fileType {
                    LabeledContent("File Type", value: fileType.uppercased())
                }
                if filter.favoritesOnly {
                    Label("Favorites Only", systemImage: "star.fill")
                        .foregroundStyle(.yellow)
                }
                if filter.printReadyOnly {
                    Label("Print Ready Only", systemImage: "checkmark.seal")
                        .foregroundStyle(.green)
                }
                if filter.needsSlicingOnly {
                    Label("Needs Slicing Only", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Filter Criteria")
            }

            Section("Results (\(matchingModels.count))") {
                if matchingModels.isEmpty {
                    Text("No models match this filter")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(matchingModels) { model in
                        HStack {
                            Image(systemName: "cube.transparent")
                                .foregroundStyle(.blue)
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.name)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    Text(model.fileType.displayName)
                                    if !model.tags.isEmpty {
                                        Text("·")
                                        Text(model.tags.prefix(3).joined(separator: ", "))
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(ByteCountFormatter.string(fromByteCount: model.fileSize, countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(filter.name)
    }
}

// MARK: - Tag Auto-Suggest View

/// An auto-suggesting tag input that offers existing tags as the user types.
struct TagAutoSuggestField: View {
    let existingTags: [String]
    @Binding var newTag: String
    let onAdd: (String) -> Void

    /// All unique tags across models minus already-added ones
    private var suggestions: [String] {
        guard !newTag.isEmpty else { return [] }
        let query = newTag.lowercased()
        return existingTags
            .filter { $0.lowercased().contains(query) }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Add tag", text: $newTag)
                    #if os(iOS)
                    .textContentType(.none)
                    #endif
                    .onSubmit {
                        addTag()
                    }

                Button {
                    addTag()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                newTag = suggestion
                                addTag()
                            } label: {
                                Text(suggestion)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onAdd(trimmed)
        newTag = ""
    }
}
