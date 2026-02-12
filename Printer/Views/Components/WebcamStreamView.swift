//
//  WebcamStreamView.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import SwiftUI

/// Displays a live webcam feed from an OctoPrint printer.
///
/// Uses periodic snapshot polling (JPEG snapshots) for broad compatibility.
/// The snapshot URL is fetched from OctoPrint's `/api/settings` endpoint.
struct WebcamStreamView: View {
    let snapshotURL: URL
    let refreshInterval: TimeInterval

    @State private var currentImage: Image?
    @State private var isLoading = true
    @State private var error: String?
    @State private var refreshTask: Task<Void, Never>?

    init(snapshotURL: URL, refreshInterval: TimeInterval = 2.0) {
        self.snapshotURL = snapshotURL
        self.refreshInterval = refreshInterval
    }

    var body: some View {
        ZStack {
            if let image = currentImage {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topTrailing) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.red)
                                .frame(width: 8, height: 8)
                            Text("LIVE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.6))
                        .clipShape(Capsule())
                        .padding(8)
                    }
            } else if isLoading {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.fill.tertiary)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        ProgressView("Connecting to camera...")
                            .font(.caption)
                    }
            } else if let error {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.fill.tertiary)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "video.slash")
                                .font(.title)
                                .foregroundStyle(.secondary)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Retry") {
                                startPolling()
                            }
                            .font(.caption)
                        }
                        .padding()
                    }
            }
        }
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
    }

    private func startPolling() {
        stopPolling()
        isLoading = true
        error = nil

        refreshTask = Task {
            while !Task.isCancelled {
                await fetchSnapshot()
                try? await Task.sleep(for: .seconds(refreshInterval))
            }
        }
    }

    private func stopPolling() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    @MainActor
    private func fetchSnapshot() async {
        do {
            var request = URLRequest(url: snapshotURL)
            request.timeoutInterval = 5
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                if currentImage == nil {
                    error = "Camera returned invalid response"
                    isLoading = false
                }
                return
            }

            #if os(macOS)
            if let nsImage = NSImage(data: data) {
                currentImage = Image(nsImage: nsImage)
                isLoading = false
                error = nil
            }
            #else
            if let uiImage = UIImage(data: data) {
                currentImage = Image(uiImage: uiImage)
                isLoading = false
                error = nil
            }
            #endif
        } catch is CancellationError {
            // Expected on disappear
        } catch {
            if currentImage == nil {
                self.error = "Cannot reach camera"
                isLoading = false
            }
        }
    }
}
