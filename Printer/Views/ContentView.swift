//
//  ContentView.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ModelListView(
                models: models,
                selectedModel: $selectedModel,
                showingScanner: $showingScanner,
                showingImporter: $showingImporter,
                showingPrintables: $showingPrintables,
                showingPrintHistory: $showingPrintHistory,
                showingPrinterSetup: $showingPrinterSetup,
                showingSettings: $showingSettings,
                showingPrintQueue: $showingPrintQueue,
                onDelete: deleteModels
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
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }
    
    private func deleteModels(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let model = models[index]
                
                // Delete the file
                Task {
                    try? await STLFileManager.shared.deleteSTL(at: model.resolvedFileURL.path)
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
            let converter = ModelConverter()
            
            for url in urls {
                // Start accessing security-scoped resource
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                
                let ext = url.pathExtension.lowercased()
                let fileType = ModelFileType.from(path: url.path)
                
                // Determine the file to import
                let importURL: URL
                if ext == "obj" || ext == "usdz" {
                    // Convert mesh formats to STL
                    if ext == "obj" {
                        importURL = try await converter.convertOBJToSTL(objURL: url)
                    } else {
                        importURL = try await converter.convertUSDZToSTL(usdzURL: url)
                    }
                } else {
                    // STL, 3MF, and sliced formats (gcode, pwmx, ctb) — import as-is
                    importURL = url
                }
                
                // Import the file
                let (fileURL, fileSize) = try await STLFileManager.shared.importSTL(from: importURL)
                
                // Generate thumbnail only for mesh formats that SceneKit can render
                let thumbnailData: Data?
                if fileType.needsSlicing && (ext == "stl" || ext == "obj" || ext == "usdz") {
                    thumbnailData = try? await converter.generateThumbnail(from: fileURL)
                } else {
                    thumbnailData = nil
                }
                
                // Store as relative path for container resilience
                let relativePath = await STLFileManager.shared.relativePath(for: fileURL)
                
                // Create model entry
                await MainActor.run {
                    let model = PrintModel(
                        name: url.deletingPathExtension().lastPathComponent,
                        fileURL: relativePath,
                        fileSize: fileSize,
                        source: .imported,
                        thumbnailData: thumbnailData
                    )
                    
                    modelContext.insert(model)
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
    @Binding var showingScanner: Bool
    @Binding var showingImporter: Bool
    @Binding var showingPrintables: Bool
    @Binding var showingPrintHistory: Bool
    @Binding var showingPrinterSetup: Bool
    @Binding var showingSettings: Bool
    @Binding var showingPrintQueue: Bool
    let onDelete: (IndexSet) -> Void

    @AppStorage("defaultSortOption") private var sortOptionRaw = "Date (Newest)"
    @State private var searchText = ""
    @State private var filterOption: ModelFilterOption = .all

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
                            showingScanner = true
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
                            showingImporter = true
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
                List(selection: $selectedModel) {
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
                        NavigationLink(value: model) {
                            ModelRowView(model: model)
                        }
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
                                    onDelete(IndexSet(integer: idx))
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Search models")
            }
        }
        .navigationTitle("3D Models")
#if os(macOS)
        .navigationSplitViewColumnWidth(min: 200, ideal: 250)
#endif
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
#endif
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingScanner = true
                    } label: {
                        Label("Scan Object", systemImage: "camera.fill")
                    }
                    
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import File", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Label("Add Model", systemImage: "plus")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingPrintables = true
                } label: {
                    Label("Printables", systemImage: "globe")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    // Sort options
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

                    // Filter options
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

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingPrintQueue = true
                } label: {
                    Label("Print Queue", systemImage: "list.number")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingPrintHistory = true
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingPrinterSetup = true
                } label: {
                    Label("Printers", systemImage: "printer")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
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
