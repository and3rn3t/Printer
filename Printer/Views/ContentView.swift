//
//  ContentView.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import OSLog

// MARK: - Shared File Import Helper

/// Import a single file URL into a `PrintModel`, handling conversion, thumbnailing, and metadata extraction.
/// Used by both file importer and drag & drop handlers.
@MainActor
@discardableResult
func importModelFile(url: URL, into context: ModelContext) async throws -> PrintModel {
    let converter = ModelConverter()
    let ext = url.pathExtension.lowercased()
    let fileType = ModelFileType.from(path: url.path)

    // Convert mesh formats if needed
    let importURL: URL
    if ext == "obj" {
        importURL = try await converter.convertOBJToSTL(objURL: url)
    } else if ext == "usdz" {
        importURL = try await converter.convertUSDZToSTL(usdzURL: url)
    } else {
        importURL = url
    }

    // Import the file
    let (fileURL, fileSize) = try await STLFileManager.shared.importSTL(from: importURL)
    let relativePath = await STLFileManager.shared.relativePath(for: fileURL)

    // Generate thumbnail
    var thumbnailData: Data?
    if fileType.needsSlicing && ["stl", "obj", "usdz"].contains(ext) {
        thumbnailData = try? await converter.generateThumbnail(from: fileURL)
    } else if fileType.isSliced {
        let parser = SlicedFileParser()
        thumbnailData = await parser.extractThumbnail(from: fileURL)
    }

    // Extract sliced file metadata
    var slicedMetadata: SlicedFileMetadata?
    if fileType.isSliced {
        let parser = SlicedFileParser()
        slicedMetadata = await parser.parseMetadata(from: fileURL)
    }

    // Create model entry (already on MainActor)
    let model = PrintModel(
        name: url.deletingPathExtension().lastPathComponent,
        fileURL: relativePath,
        fileSize: fileSize,
        source: .imported,
        thumbnailData: thumbnailData
    )
    if let metadata = slicedMetadata {
        model.applyMetadata(metadata)
    }
    context.insert(model)

    // Analyze mesh dimensions for mesh formats
    if fileType.needsSlicing {
        let analyzer = MeshAnalyzer()
        if let info = try? await analyzer.analyze(url: fileURL) {
            model.applyMeshInfo(info)
        }
    }

    return model
}

// MARK: - Content View

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PrintModel.modifiedDate, order: .reverse) private var models: [PrintModel]
    @Query private var printers: [Printer]
    
    @State private var selectedModel: PrintModel?
    @State private var showingScanner = false
    @State private var showingImporter = false
    @State private var showingPrinterSetup = false
    @State private var showingPrintHistory = false
    @State private var showingPrintables = false
    @State private var showingSettings = false
    @State private var showingPrintQueue = false
    @State private var showingStatistics = false
    @State private var showingCollections = false
    @State private var showingTagBrowser = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var selectedTab = 0
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        TabView(selection: $selectedTab) {
            // Dashboard tab
            NavigationStack {
                DashboardView()
            }
            .tabItem {
                Label("Dashboard", systemImage: "gauge.with.dots.needle.bottom.50percent")
            }
            .tag(0)

            // Library tab
            libraryContent
                .tabItem {
                    Label("Library", systemImage: "cube.transparent")
                }
                .tag(1)
        }
        .sheet(isPresented: $showingScanner) {
            ObjectScannerView { url in
                Task {
                    await handleScannedModel(url: url)
                }
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.stl, .obj, .usdz, .threeMF, .gcode, .pwmx, .ctb],
            allowsMultipleSelection: true
        ) { result in
            Task {
                await handleImportedFiles(result: result)
            }
        }
        .sheet(isPresented: $showingPrintables) {
            PrintablesBrowseView()
        }
        .sheet(isPresented: $showingPrinterSetup) {
            PrinterManagementView()
        }
        .sheet(isPresented: $showingPrintHistory) {
            NavigationStack {
                PrintHistoryView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                showingPrintHistory = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingPrintQueue) {
            PrintQueueView()
        }
        .sheet(isPresented: $showingStatistics) {
            NavigationStack {
                StatisticsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingStatistics = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingCollections) {
            CollectionListView()
        }
        .sheet(isPresented: $showingTagBrowser) {
            TagBrowserView()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    // MARK: - Library Tab Content

    @ViewBuilder
    private var libraryContent: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ModelListView(
                models: models,
                selectedModel: $selectedModel,
                actions: .init(
                    showScanner: { showingScanner = true },
                    showImporter: { showingImporter = true },
                    showPrintables: { showingPrintables = true },
                    showPrintHistory: { showingPrintHistory = true },
                    showPrinterSetup: { showingPrinterSetup = true },
                    showSettings: { showingSettings = true },
                    showPrintQueue: { showingPrintQueue = true },
                    showStatistics: { showingStatistics = true },
                    showCollections: { showingCollections = true },
                    showTagBrowser: { showingTagBrowser = true },
                    onDelete: deleteModels
                )
            )
        } detail: {
            if let model = selectedModel {
                ModelDetailView(model: model, printers: printers)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 80))
                        .foregroundStyle(.blue.gradient)

                    Text("No Model Selected")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Select a 3D model from the list or create a new one")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    HStack(spacing: 16) {
                        Button {
                            showingScanner = true
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "camera.fill")
                                    .font(.title2)
                                Text("Scan")
                                    .font(.caption)
                            }
                            .frame(width: 100, height: 80)
                            .background(.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        Button {
                            showingImporter = true
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.down.fill")
                                    .font(.title2)
                                Text("Import")
                                    .font(.caption)
                            }
                            .frame(width: 100, height: 80)
                            .background(.green.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private func deleteModels(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let model = models[index]
                
                // Delete the file
                Task {
                    do {
                        try await STLFileManager.shared.deleteSTL(at: model.resolvedFileURL.path)
                    } catch {
                        AppLogger.fileOps.error("Failed to delete file for \(model.name): \(error.localizedDescription)")
                    }
                }
                
                modelContext.delete(model)
            }
        }
    }
    
    private func handleScannedModel(url: URL) async {
        do {
            // Convert if needed (USDZ to STL)
            let converter = ModelConverter()
            let stlURL: URL
            
            if url.pathExtension.lowercased() == "usdz" {
                stlURL = try await converter.convertUSDZToSTL(usdzURL: url)
            } else {
                stlURL = url
            }
            
            // Import the file
            let (fileURL, fileSize) = try await STLFileManager.shared.importSTL(from: stlURL)
            
            // Generate thumbnail
            let thumbnailData = try? await converter.generateThumbnail(from: fileURL)
            
            // Store as relative path for container resilience
            let relativePath = await STLFileManager.shared.relativePath(for: fileURL)
            
            // Create model entry
            await MainActor.run {
                let model = PrintModel(
                    name: "Scanned Object \(Date().formatted(date: .numeric, time: .shortened))",
                    fileURL: relativePath,
                    fileSize: fileSize,
                    source: .scanned,
                    thumbnailData: thumbnailData
                )
                
                modelContext.insert(model)
                selectedModel = model
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to process scanned model: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
    
    private func handleImportedFiles(result: Result<[URL], Error>) async {
        do {
            let urls = try result.get()
            
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                
                let model = try await importModelFile(url: url, into: modelContext)
                await MainActor.run {
                    selectedModel = model
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to import file: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
}

// MARK: - Model List View

struct ModelListView: View {
    let models: [PrintModel]
    @Binding var selectedModel: PrintModel?

    /// Actions the list can trigger on its parent
    struct Actions {
        var showScanner: () -> Void = {}
        var showImporter: () -> Void = {}
        var showPrintables: () -> Void = {}
        var showPrintHistory: () -> Void = {}
        var showPrinterSetup: () -> Void = {}
        var showSettings: () -> Void = {}
        var showPrintQueue: () -> Void = {}
        var showStatistics: () -> Void = {}
        var showCollections: () -> Void = {}
        var showTagBrowser: () -> Void = {}
        var onDelete: (IndexSet) -> Void = { _ in }
    }

    var actions: Actions

    @Environment(\.modelContext) private var modelContext
    @AppStorage("defaultSortOption") private var sortOptionRaw = "Date (Newest)"
    @State private var searchText = ""
    @State private var filterOption: ModelFilterOption = .all
    @State private var isSelectMode = false
    @State private var selectedModelIDs: Set<UUID> = []
    @State private var batchTagText = ""
    @State private var showingBatchTag = false
    @State private var showingBatchCollectionPicker = false

    private var sortOption: ModelSortOption {
        ModelSortOption(rawValue: sortOptionRaw) ?? .dateNewest
    }

    /// Models filtered and sorted by current user selections
    private var filteredModels: [PrintModel] {
        var result = models

        // Filter
        switch filterOption {
        case .all: break
        case .scanned: result = result.filter { $0.source == .scanned }
        case .imported: result = result.filter { $0.source == .imported }
        case .downloaded: result = result.filter { $0.source == .downloaded }
        case .favorites: result = result.filter { $0.isFavorite }
        case .needsSlicing: result = result.filter { $0.requiresSlicing }
        case .sliced: result = result.filter { !$0.requiresSlicing }
        }

        // Search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                $0.notes.lowercased().contains(query) ||
                $0.tags.contains(where: { $0.lowercased().contains(query) })
            }
        }

        // Sort
        switch sortOption {
        case .dateNewest: result.sort { $0.modifiedDate > $1.modifiedDate }
        case .dateOldest: result.sort { $0.modifiedDate < $1.modifiedDate }
        case .nameAZ: result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameZA: result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .sizeLargest: result.sort { $0.fileSize > $1.fileSize }
        case .sizeSmallest: result.sort { $0.fileSize < $1.fileSize }
        case .printCount: result.sort { $0.printJobs.count > $1.printJobs.count }
        }

        return result
    }
    
    var body: some View {
        Group {
            if models.isEmpty {
                // Empty state
                VStack(spacing: 24) {
                    Spacer()
                    
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 70))
                        .foregroundStyle(.blue.gradient)
                    
                    VStack(spacing: 8) {
                        Text("No Models Yet")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Start by scanning an object or importing a file")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    VStack(spacing: 12) {
                        Button {
                            actions.showScanner()
                        } label: {
                            HStack {
                                Image(systemName: "camera.fill")
                                Text("Scan Object")
                            }
                            .frame(maxWidth: 200)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        
                        Button {
                            actions.showImporter()
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.down.fill")
                                Text("Import File")
                            }
                            .frame(maxWidth: 200)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    
                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
#if os(iOS)
                .background(Color(.systemGroupedBackground))
#endif
            } else {
                ZStack(alignment: .bottom) {
                    List(selection: isSelectMode ? nil : $selectedModel) {
                        // Filter chips
                        if !searchText.isEmpty || filterOption != .all {
                            HStack {
                                Text("\(filteredModels.count) of \(models.count) models")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if filterOption != .all {
                                    Button {
                                        filterOption = .all
                                    } label: {
                                        Label("Clear Filter", systemImage: "xmark.circle.fill")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .listRowSeparator(.hidden)
                        }

                        ForEach(filteredModels) { model in
                            if isSelectMode {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedModelIDs.contains(model.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedModelIDs.contains(model.id) ? .blue : .secondary)
                                        .font(.title3)
                                    ModelRowView(model: model)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        if selectedModelIDs.contains(model.id) {
                                            selectedModelIDs.remove(model.id)
                                        } else {
                                            selectedModelIDs.insert(model.id)
                                        }
                                    }
                                }
                            } else {
                                NavigationLink(value: model) {
                                    ModelRowView(model: model)
                                }
                                .draggable(model)
                                .swipeActions(edge: .leading) {
                                    Button {
                                        model.isFavorite.toggle()
                                    } label: {
                                        Label(
                                            model.isFavorite ? "Unfavorite" : "Favorite",
                                            systemImage: model.isFavorite ? "star.slash" : "star.fill"
                                        )
                                    }
                                    .tint(.yellow)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        if let idx = models.firstIndex(of: model) {
                                            actions.onDelete(IndexSet(integer: idx))
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search models")
                    .dropDestination(for: URL.self) { urls, _ in
                        handleDroppedURLs(urls)
                        return true
                    }

                    // Batch action bar
                    if isSelectMode && !selectedModelIDs.isEmpty {
                        batchActionBar
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .navigationTitle("3D Models")
#if os(macOS)
        .navigationSplitViewColumnWidth(min: 200, ideal: 250)
#endif
        .toolbar {
            modelListToolbar
        }
        .alert("Add Tag", isPresented: $showingBatchTag) {
            TextField("Tag name", text: $batchTagText)
            Button("Cancel", role: .cancel) { batchTagText = "" }
            Button("Add") {
                batchAddTag(batchTagText)
                batchTagText = ""
            }
        } message: {
            Text("Add a tag to \(selectedModelIDs.count) selected models")
        }
        .sheet(isPresented: $showingBatchCollectionPicker) {
            BatchAddToCollectionView(modelIDs: selectedModelIDs, allModels: models)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var modelListToolbar: some ToolbarContent {
#if os(iOS)
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(isSelectMode ? "Done" : "Select") {
                withAnimation {
                    isSelectMode.toggle()
                    if !isSelectMode {
                        selectedModelIDs.removeAll()
                    }
                }
            }
        }
#endif
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    actions.showScanner()
                } label: {
                    Label("Scan Object", systemImage: "camera.fill")
                }

                Button {
                    actions.showImporter()
                } label: {
                    Label("Import File", systemImage: "square.and.arrow.down")
                }
            } label: {
                Label("Add Model", systemImage: "plus")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                actions.showPrintables()
            } label: {
                Label("Printables", systemImage: "globe")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            sortFilterMenu
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                actions.showPrintQueue()
            } label: {
                Label("Print Queue", systemImage: "list.number")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    actions.showPrintHistory()
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

                Button {
                    actions.showStatistics()
                } label: {
                    Label("Statistics", systemImage: "chart.bar.fill")
                }

                Button {
                    actions.showCollections()
                } label: {
                    Label("Collections", systemImage: "folder")
                }

                Button {
                    actions.showTagBrowser()
                } label: {
                    Label("Tags", systemImage: "tag")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                actions.showPrinterSetup()
            } label: {
                Label("Printers", systemImage: "printer")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                actions.showSettings()
            } label: {
                Label("Settings", systemImage: "gear")
            }
        }
    }

    private var sortFilterMenu: some View {
        Menu {
            Section("Sort By") {
                ForEach(ModelSortOption.allCases) { option in
                    Button {
                        sortOptionRaw = option.rawValue
                    } label: {
                        HStack {
                            Text(option.rawValue)
                            if sortOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Section("Filter") {
                ForEach(ModelFilterOption.allCases) { option in
                    Button {
                        filterOption = option
                    } label: {
                        HStack {
                            Text(option.rawValue)
                            if filterOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            Label("Sort & Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    // MARK: - Batch Actions

    @ViewBuilder
    private var batchActionBar: some View {
        HStack(spacing: 16) {
            Text("\(selectedModelIDs.count) selected")
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()

            Button {
                batchToggleFavorite()
            } label: {
                Image(systemName: "star.fill")
            }
            .foregroundStyle(.yellow)

            Button {
                showingBatchTag = true
            } label: {
                Image(systemName: "tag.fill")
            }
            .foregroundStyle(.blue)

            Button {
                showingBatchCollectionPicker = true
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .foregroundStyle(.purple)

            Button(role: .destructive) {
                batchDelete()
            } label: {
                Image(systemName: "trash.fill")
            }
            .foregroundStyle(.red)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func batchToggleFavorite() {
        let selected = models.filter { selectedModelIDs.contains($0.id) }
        let allFavorited = selected.allSatisfy(\.isFavorite)
        withAnimation {
            for model in selected {
                model.isFavorite = !allFavorited
            }
        }
    }

    private func batchAddTag(_ tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let selected = models.filter { selectedModelIDs.contains($0.id) }
        for model in selected {
            if !model.tags.contains(trimmed) {
                model.tags.append(trimmed)
            }
        }
    }

    private func batchDelete() {
        withAnimation {
            for model in models where selectedModelIDs.contains(model.id) {
                if let idx = models.firstIndex(of: model) {
                    actions.onDelete(IndexSet(integer: idx))
                }
            }
            selectedModelIDs.removeAll()
            isSelectMode = false
        }
    }

    /// Handle URLs dropped onto the model list (drag & drop import)
    private func handleDroppedURLs(_ urls: [URL]) {
        let context = modelContext
        Task {
            let supported = Set(["stl", "obj", "usdz", "3mf", "gcode", "pwmx", "pwma", "ctb"])

            for url in urls {
                let ext = url.pathExtension.lowercased()
                guard supported.contains(ext) else { continue }

                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }

                guard FileManager.default.fileExists(atPath: url.path) else { continue }

                do {
                    try await importModelFile(url: url, into: context)
                } catch {
                    AppLogger.fileOps.error("Drag-and-drop import failed for \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Batch Add to Collection

/// Sheet for adding multiple selected models to a collection at once.
struct BatchAddToCollectionView: View {
    let modelIDs: Set<UUID>
    let allModels: [PrintModel]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ModelCollection.name) private var collections: [ModelCollection]

    var body: some View {
        NavigationStack {
            Group {
                if collections.isEmpty {
                    ContentUnavailableView(
                        "No Collections",
                        systemImage: "folder.badge.plus",
                        description: Text("Create a collection first in the Collections view")
                    )
                } else {
                    List {
                        ForEach(collections) { collection in
                            Button {
                                addToCollection(collection)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: collection.icon)
                                        .foregroundStyle(Color(hex: collection.colorHex) ?? .blue)
                                    Text(collection.name)
                                    Spacer()
                                    Text("\(collection.models.count)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Add to Collection")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func addToCollection(_ collection: ModelCollection) {
        let selected = allModels.filter { modelIDs.contains($0.id) }
        let existingIDs = Set(collection.models.map(\.id))
        for model in selected {
            if !existingIDs.contains(model.id) {
                collection.models.append(model)
            }
        }
        collection.modifiedDate = Date()
    }
}

// MARK: - Model Row

struct ModelRowView: View {
    let model: PrintModel
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail with gradient placeholder
            Group {
                if let thumbnailData = model.thumbnailData {
#if os(macOS)
                    if let nsImage = NSImage(data: thumbnailData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
#else
                    if let uiImage = UIImage(data: thumbnailData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
#endif
                } else {
                    ZStack {
                        LinearGradient(
                            colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        
                        Image(systemName: "cube.transparent")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            .overlay(alignment: .topTrailing) {
                if model.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .padding(2)
                        .background(.ultraThinMaterial, in: Circle())
                        .offset(x: 4, y: -4)
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(model.name)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Label {
                        Text(model.source.displayText)
                    } icon: {
                        Image(systemName: model.source.icon)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    
                    Text("•")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    
                    Text(ByteCountFormatter.string(fromByteCount: model.fileSize, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // File type badge
                    Text(model.fileType.displayName)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(model.requiresSlicing ? Color.orange.opacity(0.15) : Color.green.opacity(0.15))
                        .foregroundStyle(model.requiresSlicing ? .orange : .green)
                        .clipShape(Capsule())

                    // Pre-sliced indicator for downloaded sliced files
                    if model.fileType.isSliced && model.hasSlicedMetadata {
                        Label("Sliced", systemImage: "checkmark.seal.fill")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }
                
                if !model.printJobs.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "printer.fill")
                            .font(.caption2)
                        Text("\(model.printJobs.count) print\(model.printJobs.count == 1 ? "" : "s")")
                            .font(.caption2)
                    }
                    .foregroundStyle(.blue)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
    
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: PrintModel.self, PrintJob.self, Printer.self,
        configurations: config
    )
    
    return ContentView()
        .modelContainer(container)
}
