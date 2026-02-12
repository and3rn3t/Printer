//
//  ObjectScannerView.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import SwiftUI
import AVFoundation
import Combine

#if os(iOS)

/// View for scanning 3D objects using photogrammetry
/// Note: Full Object Capture API requires macOS. On iOS, we provide a simplified capture interface.
struct ObjectScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scanManager = ObjectScanManager()

    let onComplete: (URL) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if scanManager.isLiDARAvailable {
                    VStack(spacing: 16) {
                        Image(systemName: "camera.metering.center.weighted")
                            .font(.system(size: 80))
                            .foregroundStyle(.blue)

                        Text("3D Scanning")
                            .font(.title)
                            .fontWeight(.bold)

                        Text("For full 3D object scanning with LiDAR, use a dedicated scanning app like:")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 12) {
                            ScanningAppRow(
                                name: "Polycam",
                                description: "Free LiDAR scanning"
                            )

                            ScanningAppRow(
                                name: "3D Scanner App",
                                description: "Easy to use scanning"
                            )

                            ScanningAppRow(
                                name: "Scaniverse",
                                description: "High-quality captures"
                            )
                        }
                        .padding()
                        .background(.fill.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Text("Then export your scan as STL or OBJ and import it into this app.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)

                        Spacer()
                    }
                    .padding()
                } else {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 60))
                        .foregroundStyle(.orange)

                    Text("LiDAR Not Available")
                        .font(.title2)

                    Text("This device does not have a LiDAR sensor. You can still import 3D models from other sources.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
            }
            .navigationTitle("Scan Object")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ScanningAppRow: View {
    let name: String
    let description: String

    var body: some View {
        HStack {
            Image(systemName: "app.badge")
                .foregroundStyle(.blue)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

/// Manages device capabilities for scanning
@MainActor
@Observable
class ObjectScanManager {
    var error: Error?

    var isLiDARAvailable: Bool {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInLiDARDepthCamera],
            mediaType: .video,
            position: .back
        ).devices

        return !devices.isEmpty
    }
}

#else
// Placeholder for macOS
struct ObjectScannerView: View {
    let onComplete: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("Not Available")
                .font(.title2)

            Text("3D object scanning is only available on iOS devices with LiDAR.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Dismiss") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}
#endif
