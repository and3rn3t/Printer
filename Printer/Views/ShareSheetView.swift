//
//  ShareSheetView.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import SwiftUI

#if os(iOS) || os(visionOS)
import UIKit

/// A simple UIActivityViewController wrapper for sharing items.
struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#elseif os(macOS)
import AppKit

/// macOS share sheet using NSSharingServicePicker.
struct ShareSheetView: View {
    let items: [Any]

    var body: some View {
        VStack(spacing: 16) {
            Text("Export Complete")
                .font(.headline)

            if let url = items.first as? URL {
                Text(url.lastPathComponent)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
    }
}
#endif
