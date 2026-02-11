//
//  PrintablesBrowseView.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import SwiftUI

/// Browse and search the Printables.com model library.
///
/// Users can search by keyword, change sort order, tap a result to see details,
/// and download STL files directly into the local model library.
struct PrintablesBrowseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var submittedQuery = ""
    @State private var results: [PrintablesSearchResult] = []
    @State private var isLoading = false
    @State private var hasSearched = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var ordering: PrintablesOrdering = .bestMatch
    @State private var offset = 0
    @State private var canLoadMore = true
    @State private var selectedResult: IdentifiableString?

    private let service = PrintablesService()
    private let pageSize = 20

    var body: some View {
        NavigationStack {
            Group {
                if !hasSearched && results.isEmpty {
                    emptyState
                } else if isLoading && results.isEmpty {
                    loadingState
                } else if results.isEmpty && hasSearched {
                    noResultsState
                } else {
                    resultsList
                }
            }
            .navigationTitle("Printables")
#if os(iOS)
            .navigationBarTitleDisplayMode(.large)
#endif
            .searchable(text: $searchText, prompt: "Search models...")
            .onSubmit(of: .search) {
                performSearch(reset: true)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Sort By", selection: $ordering) {
                            ForEach(PrintablesOrdering.allCases) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
            .onChange(of: ordering) {
                if hasSearched {
                    performSearch(reset: true)
                }
            }
            .sheet(item: $selectedResult) { result in
                NavigationStack {
                    PrintablesDetailView(modelID: result.id)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
        }
    }

    // MARK: - States

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "globe")
                .font(.system(size: 60))
                .foregroundStyle(.blue.gradient)

            Text("Explore Printables.com")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Search thousands of free 3D models ready to download and print")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Quick-search suggestions
            VStack(spacing: 10) {
                Text("Try searching for:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    ForEach(["Benchy", "Vase", "Phone Stand"], id: \.self) { suggestion in
                        Button(suggestion) {
                            searchText = suggestion
                            performSearch(reset: true)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Searching Printables...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var noResultsState: some View {
        ContentUnavailableView.search(text: submittedQuery)
    }

    // MARK: - Results List

    @ViewBuilder
    private var resultsList: some View {
        List {
            Section {
                ForEach(results) { result in
                    Button {
                        selectedResult = IdentifiableString(id: result.id)
                    } label: {
                        PrintablesResultRow(result: result)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                if !submittedQuery.isEmpty {
                    Text("Results for \"\(submittedQuery)\"")
                }
            }

            // Load more
            if canLoadMore && !results.isEmpty {
                Section {
                    Button {
                        loadMore()
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 8)
                            }
                            Text(isLoading ? "Loading..." : "Load More")
                                .font(.subheadline)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled(isLoading)
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Actions

    private func performSearch(reset: Bool) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        if reset {
            results = []
            offset = 0
            canLoadMore = true
            submittedQuery = query
        }

        isLoading = true
        hasSearched = true

        Task {
            do {
                let items = try await service.search(
                    query: query,
                    limit: pageSize,
                    offset: offset,
                    ordering: ordering
                )

                await MainActor.run {
                    if reset {
                        results = items
                    } else {
                        results.append(contentsOf: items)
                    }
                    canLoadMore = items.count == pageSize
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isLoading = false
                }
            }
        }
    }

    private func loadMore() {
        offset += pageSize
        performSearch(reset: false)
    }
}

// MARK: - Search Result Row

struct PrintablesResultRow: View {
    let result: PrintablesSearchResult

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            AsyncImage(url: result.image.imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    placeholderImage
                case .empty:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                @unknown default:
                    placeholderImage
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(result.name)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    Label("\(result.likesCount)", systemImage: "heart.fill")
                        .foregroundStyle(.pink)

                    Label("\(result.downloadCount)", systemImage: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                }
                .font(.caption)

                Text(result.formattedDate)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if result.hasSlicedFiles {
                    Label("Slice Ready", systemImage: "checkmark.seal.fill")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var placeholderImage: some View {
        ZStack {
            Color.gray.opacity(0.15)
            Image(systemName: "cube.transparent")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Helper

/// Simple wrapper to make a String work with `.sheet(item:)`
struct IdentifiableString: Identifiable {
    let id: String
}
