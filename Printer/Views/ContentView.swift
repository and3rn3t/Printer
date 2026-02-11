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
            allowedContentTypes: [.stl, .obj, .usdz],
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
                    ForEach(models) { model in
                        NavigationLink(value: model) {
                            ModelRowView(model: model)
                        }
                    }
                    .onDelete(perform: onDelete)
                }
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
            
            VStack(alignment: .leading, spacing: 6) {
                Text(model.name)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Label {
                        Text(sourceText(for: model.source))
                    } icon: {
                        Image(systemName: sourceIcon(for: model.source))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    
                    Text("•")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    
                    Text(ByteCountFormatter.string(fromByteCount: model.fileSize, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
    
    private func sourceIcon(for source: ModelSource) -> String {
        switch source {
        case .scanned: return "camera.fill"
        case .imported: return "square.and.arrow.down.fill"
        case .downloaded: return "arrow.down.circle.fill"
        }
    }
    
    private func sourceText(for source: ModelSource) -> String {
        switch source {
        case .scanned: return "Scanned"
        case .imported: return "Imported"
        case .downloaded: return "Downloaded"
        }
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
