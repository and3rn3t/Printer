//
//  PrintablesDetailView.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import SwiftUI
import SwiftData

/// Full detail view for a single Printables model.
///
/// Shows images, description, author, tags, and downloadable files (STL/SLA).
/// Users can download files directly into their local model library.
struct PrintablesDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let modelID: String

    @State private var detail: PrintablesModelDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var downloadingFileID: String?
    @State private var downloadSuccess = false

    private let service = PrintablesService()

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading details...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail {
                detailContent(detail)
            } else {
                ContentUnavailableView(
                    "Failed to Load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage ?? "Unknown error")
                )
            }
        }
        .navigationTitle(detail?.name ?? "Model Detail")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task {
            await loadDetail()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .alert("Downloaded!", isPresented: $downloadSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("The file has been added to your model library.")
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    // swiftlint:disable:next cyclomatic_complexity
    private func detailContent(_ model: PrintablesModelDetail) -> some View {
        List {
            // Image gallery
            if let images = model.images, !images.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(images) { image in
                                AsyncImage(url: image.imageURL) { phase in
                                    switch phase {
                                    case .success(let img):
                                        img
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                    case .failure:
                                        imagePlaceholder
                                    case .empty:
                                        ProgressView()
                                            .frame(width: 280, height: 200)
                                    @unknown default:
                                        imagePlaceholder
                                    }
                                }
                                .frame(height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }

            // Stats
            Section("Stats") {
                HStack(spacing: 24) {
                    statItem(icon: "heart.fill", value: "\(model.likesCount)", label: "Likes", color: .pink)
                    statItem(
                        icon: "arrow.down.circle.fill",
                        value: "\(model.downloadCount)",
                        label: "Downloads",
                        color: .blue
                    )
                    statItem(icon: "wrench.fill", value: "\(model.makesCount)", label: "Makes", color: .orange)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }

            // Author
            if let user = model.user {
                Section("Author") {
                    HStack(spacing: 12) {
                        AsyncImage(url: user.avatarURL) { phase in
                            if case .success(let img) = phase {
                                img.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.publicUsername)
                                .font(.headline)
                            Text("@\(user.handle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if let profileURL = URL(string: "https://www.printables.com/@\(user.handle)") {
                            Link(destination: profileURL) {
                                Label("Profile", systemImage: "arrow.up.right.square")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }

            // Summary
            if let summary = model.summary, !summary.isEmpty {
                Section("Summary") {
                    Text(summary)
                        .font(.body)
                }
            }

            // Category & Tags
            if let tags = model.tags, !tags.isEmpty {
                Section("Tags") {
                    FlowLayout(spacing: 8) {
                        ForEach(tags) { tag in
                            Text(tag.name)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            // Category
            if let category = model.category, let path = category.path {
                let categoryText = path.compactMap(\.name).joined(separator: " > ")
                if !categoryText.isEmpty {
                    Section("Category") {
                        Label(categoryText, systemImage: "folder")
                            .font(.subheadline)
                    }
                }
            }

            // License
            if let license = model.license, let licenseName = license.name {
                Section("License") {
                    Label(licenseName, systemImage: "doc.text")
                        .font(.subheadline)
                }
            }

            // STL Files
            if let stls = model.stls, !stls.isEmpty {
                Section("STL Files") {
                    ForEach(stls) { file in
                        fileRow(file: file, icon: "doc.zipper", modelName: model.name, printId: model.id, fileType: "stl")
                    }
                }
            }

            // SLA Files
            if let slas = model.slas, !slas.isEmpty {
                Section("SLA Files") {
                    ForEach(slas) { file in
                        fileRow(file: file, icon: "cube.fill", modelName: model.name, printId: model.id, fileType: "sla")
                    }
                }
            }

            // GCode Files
            if let gcodes = model.gcodes, !gcodes.isEmpty {
                Section("GCode Files") {
                    ForEach(gcodes) { file in
                        fileRow(file: file, icon: "printer.fill", modelName: model.name, printId: model.id, fileType: "gcode")
                    }
                }
            }

            // Open in Browser
            Section {
                if let browseURL = URL(string: "https://www.printables.com/model/\(model.id)") {
                    Link(destination: browseURL) {
                        Label("View on Printables.com", systemImage: "safari")
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func statItem(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func fileRow(
        file: PrintablesFile,
        icon: String,
        modelName: String,
        printId: String,
        fileType: String
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(file.formattedFileSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if downloadingFileID == file.id {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    downloadAndImport(file: file, modelName: modelName, printId: printId, fileType: fileType)
                } label: {
                    Image(systemName: "arrow.down.to.line")
                        .font(.body)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var imagePlaceholder: some View {
        ZStack {
            Color.gray.opacity(0.12)
            Image(systemName: "photo")
                .font(.title)
                .foregroundStyle(.secondary)
        }
        .frame(width: 280, height: 200)
    }

    // MARK: - Actions

    private func loadDetail() async {
        do {
            let model = try await service.modelDetail(id: modelID)
            await MainActor.run {
                detail = model
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func downloadAndImport(file: PrintablesFile, modelName: String, printId: String, fileType: String) {
        downloadingFileID = file.id

        Task {
            do {
                // Download the file via signed link
                let localURL = try await service.downloadFile(file, printId: printId, fileType: fileType)

                // Import into the local model library
                let (savedURL, fileSize) = try await STLFileManager.shared.importSTL(from: localURL)
                let relativePath = await STLFileManager.shared.relativePath(for: savedURL)

                // Use the Printables model image as thumbnail (more reliable than SceneKit rendering)
                var thumbnailData: Data?
                if let imageURL = detail?.images?.first?.imageURL {
                    thumbnailData = try? await URLSession.shared.data(from: imageURL).0
                }

                // Fall back to SceneKit rendering if no image available
                if thumbnailData == nil {
                    let converter = ModelConverter()
                    thumbnailData = try? await converter.generateThumbnail(from: savedURL)
                }

                // Extract sliced file metadata if applicable
                let fileModelType = ModelFileType.from(path: savedURL.path)

                // Fall back to embedded sliced file thumbnail
                if thumbnailData == nil && fileModelType.isSliced {
                    let parser = SlicedFileParser()
                    thumbnailData = await parser.extractThumbnail(from: savedURL)
                }

                var slicedMetadata: SlicedFileMetadata?
                if fileModelType.isSliced {
                    let parser = SlicedFileParser()
                    slicedMetadata = await parser.parseMetadata(from: savedURL)
                }

                await MainActor.run {
                    let printModel = PrintModel(
                        name: modelName,
                        fileURL: relativePath,
                        fileSize: fileSize,
                        source: .downloaded,
                        thumbnailData: thumbnailData
                    )

                    if let metadata = slicedMetadata {
                        printModel.applyMetadata(metadata)
                    }

                    modelContext.insert(printModel)

                    downloadingFileID = nil
                    downloadSuccess = true
                }

                // Clean up temp file
                try? FileManager.default.removeItem(at: localURL)
            } catch {
                await MainActor.run {
                    downloadingFileID = nil
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
}

// FlowLayout is defined in Views/Components/FlowLayout.swift
