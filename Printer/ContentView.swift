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
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ModelListView(
                models: models,
                selectedModel: $selectedModel,
                showingScanner: $showingScanner,
                showingImporter: $showingImporter,
                onDelete: deleteModels
            )
        } detail: {
            if let model = selectedModel {
                ModelDetailView(model: model, printers: printers)
            } else {
                ContentUnavailableView(
                    "No Model Selected",
                    systemImage: "cube.transparent",
                    description: Text("Select a 3D model from the list or create a new scan")
                )
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
            allowedContentTypes: [.stl, UTType(filenameExtension: "obj") ?? .data],
            allowsMultipleSelection: true
        ) { result in
            Task {
                await handleImportedFiles(result: result)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingPrinterSetup = true
                } label: {
                    Label("Printers", systemImage: "printer")
                }
            }
        }
        .sheet(isPresented: $showingPrinterSetup) {
            PrinterManagementView()
        }
    }
    
    private func deleteModels(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let model = models[index]
                
                // Delete the file
                Task {
                    try? await STLFileManager.shared.deleteSTL(at: model.fileURL)
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
            
            // Create model entry
            await MainActor.run {
                let model = PrintModel(
                    name: "Scanned Object \(Date().formatted(date: .numeric, time: .shortened))",
                    fileURL: fileURL.path,
                    fileSize: fileSize,
                    source: .scanned,
                    thumbnailData: thumbnailData
                )
                
                modelContext.insert(model)
                selectedModel = model
            }
        } catch {
            print("Error handling scanned model: \(error)")
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
                
                // Convert if needed
                let stlURL: URL
                let ext = url.pathExtension.lowercased()
                
                if ext == "obj" || ext == "usdz" {
                    if ext == "obj" {
                        stlURL = try await converter.convertOBJToSTL(objURL: url)
                    } else {
                        stlURL = try await converter.convertUSDZToSTL(usdzURL: url)
                    }
                } else {
                    stlURL = url
                }
                
                // Import the file
                let (fileURL, fileSize) = try await STLFileManager.shared.importSTL(from: stlURL)
                
                // Generate thumbnail
                let thumbnailData = try? await converter.generateThumbnail(from: fileURL)
                
                // Create model entry
                await MainActor.run {
                    let model = PrintModel(
                        name: url.deletingPathExtension().lastPathComponent,
                        fileURL: fileURL.path,
                        fileSize: fileSize,
                        source: .imported,
                        thumbnailData: thumbnailData
                    )
                    
                    modelContext.insert(model)
                    selectedModel = model
                }
            }
        } catch {
            print("Error importing files: \(error)")
        }
    }
}

// MARK: - Model List View

struct ModelListView: View {
    let models: [PrintModel]
    @Binding var selectedModel: PrintModel?
    @Binding var showingScanner: Bool
    @Binding var showingImporter: Bool
    let onDelete: (IndexSet) -> Void
    
    var body: some View {
        List(selection: $selectedModel) {
            ForEach(models) { model in
                NavigationLink(value: model) {
                    ModelRowView(model: model)
                }
            }
            .onDelete(perform: onDelete)
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
            ToolbarItem {
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
        }
    }
}

// MARK: - Model Row

struct ModelRowView: View {
    let model: PrintModel
    
    var body: some View {
        HStack {
            if let thumbnailData = model.thumbnailData {
#if os(macOS)
                if let nsImage = NSImage(data: thumbnailData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
#else
                if let uiImage = UIImage(data: thumbnailData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
#endif
            } else {
                Image(systemName: "cube")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 50, height: 50)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .font(.headline)
                
                HStack {
                    Image(systemName: sourceIcon(for: model.source))
                        .font(.caption)
                    
                    Text(ByteCountFormatter.string(fromByteCount: model.fileSize, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private func sourceIcon(for source: ModelSource) -> String {
        switch source {
        case .scanned: return "camera.fill"
        case .imported: return "square.and.arrow.down"
        case .downloaded: return "arrow.down.circle"
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: PrintModel.self, inMemory: true)
}
