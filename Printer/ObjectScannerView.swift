//
//  ObjectScannerView.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import SwiftUI
import RealityKit

#if os(iOS)
import ObjectCaptureKit

/// View for scanning 3D objects using LiDAR and camera
struct ObjectScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanManager = ObjectScanManager()
    
    let onComplete: (URL) -> Void
    
    var body: some View {
        ZStack {
            if scanManager.isSupported {
                ObjectCaptureView(
                    session: scanManager.session,
                    cameraFeedOverlay: {
                        ScanOverlayView(
                            state: scanManager.state,
                            feedback: scanManager.feedback
                        )
                    }
                )
                .onAppear {
                    scanManager.startSession()
                }
                .onDisappear {
                    scanManager.cancelSession()
                }
                
                VStack {
                    Spacer()
                    
                    HStack {
                        Button("Cancel") {
                            scanManager.cancelSession()
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        if scanManager.canCapture {
                            Button("Capture") {
                                scanManager.capture()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        
                        if scanManager.canFinish {
                            Button("Finish") {
                                Task {
                                    await scanManager.finishSession { url in
                                        if let url = url {
                                            onComplete(url)
                                            dismiss()
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding()
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 60))
                        .foregroundStyle(.orange)
                    
                    Text("LiDAR Not Available")
                        .font(.title2)
                    
                    Text("This device does not support 3D object scanning. You need a device with LiDAR sensor.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                    
                    Button("Dismiss") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
        }
        .alert("Scan Error", isPresented: .init(
            get: { scanManager.error != nil },
            set: { if !$0 { scanManager.error = nil } }
        )) {
            Button("OK") {
                scanManager.error = nil
            }
        } message: {
            if let error = scanManager.error {
                Text(error.localizedDescription)
            }
        }
    }
}

/// Overlay UI for scan feedback
struct ScanOverlayView: View {
    let state: ObjectScanManager.ScanState
    let feedback: String?
    
    var body: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(state.description)
                        .font(.headline)
                        .foregroundStyle(.white)
                    
                    if let feedback = feedback {
                        Text(feedback)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                
                Spacer()
            }
            .padding()
            
            Spacer()
        }
    }
}

/// Manages the object scanning session
@MainActor
class ObjectScanManager: ObservableObject {
    @Published var state: ScanState = .ready
    @Published var feedback: String?
    @Published var error: Error?
    
    private(set) var session: ObjectCaptureSession?
    
    enum ScanState: Equatable {
        case ready
        case detecting
        case capturing
        case processing
        case completed
        
        var description: String {
            switch self {
            case .ready:
                return "Point camera at object"
            case .detecting:
                return "Detecting object..."
            case .capturing:
                return "Capturing"
            case .processing:
                return "Processing..."
            case .completed:
                return "Scan complete!"
            }
        }
    }
    
    var isSupported: Bool {
        ObjectCaptureSession.isSupported
    }
    
    var canCapture: Bool {
        state == .detecting || state == .capturing
    }
    
    var canFinish: Bool {
        state == .capturing
    }
    
    func startSession() {
        guard isSupported else { return }
        
        do {
            let session = ObjectCaptureSession()
            self.session = session
            
            Task {
                do {
                    try await session.start()
                    state = .detecting
                } catch {
                    self.error = error
                }
            }
        }
    }
    
    func capture() {
        // Signal to capture frame
        state = .capturing
        feedback = "Keep moving around the object"
    }
    
    func finishSession(completion: @escaping (URL?) -> Void) async {
        state = .processing
        
        guard let session = session else {
            completion(nil)
            return
        }
        
        do {
            // Request the reconstructed model
            let result = try await session.process(
                configuration: ObjectCaptureSession.Configuration(
                    objectDetail: .medium,
                    isObjectFlippingAllowed: true
                )
            )
            
            // Export as STL
            let stlURL = try await exportToSTL(result: result)
            
            state = .completed
            completion(stlURL)
        } catch {
            self.error = error
            completion(nil)
        }
    }
    
    func cancelSession() {
        session?.cancel()
        session = nil
    }
    
    private func exportToSTL(result: ObjectCaptureSession.Output) async throws -> URL {
        // Get temporary directory
        let tempDir = FileManager.default.temporaryDirectory
        let stlURL = tempDir.appendingPathComponent("\(UUID().uuidString).stl")
        
        // Export the mesh to STL format
        // Note: ObjectCaptureKit provides USDZ, you'll need to convert to STL
        // For now, we'll save the USDZ and note that conversion is needed
        let usdzURL = tempDir.appendingPathComponent("\(UUID().uuidString).usdz")
        
        try await result.model.write(to: usdzURL)
        
        // TODO: Implement USDZ to STL conversion
        // For now, return the USDZ URL
        // You may want to use ModelIO or a third-party library for conversion
        
        return usdzURL
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
