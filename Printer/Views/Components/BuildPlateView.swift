//
//  BuildPlateView.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import SwiftUI

/// A 2D top-down visualization of how a model's XY footprint fits on a printer's build plate.
///
/// Color-coded by utilization:
/// - Green: < 50% utilization
/// - Yellow: 50–80% utilization
/// - Red: > 80% utilization or doesn't fit
///
/// For resin printers, highlights the center FEP stress zone.
struct BuildPlateView: View {
    /// Build plate dimensions in mm
    let plateX: Float
    let plateY: Float
    let plateZ: Float

    /// Model dimensions in mm
    let modelX: Float
    let modelY: Float
    let modelZ: Float

    /// Whether this is a resin printer (shows FEP stress zone)
    var isResinPrinter: Bool = false

    /// Whether the model fits on the build plate
    private var fits: Bool {
        modelX <= plateX && modelY <= plateY && modelZ <= plateZ
    }

    /// Utilization percentage (area coverage)
    private var utilization: Double {
        guard plateX > 0 && plateY > 0 else { return 0 }
        return Double(modelX * modelY) / Double(plateX * plateY)
    }

    /// Height utilization
    private var heightUtilization: Double {
        guard plateZ > 0 else { return 0 }
        return Double(modelZ) / Double(plateZ)
    }

    /// Primary color based on utilization and fit
    private var utilizationColor: Color {
        if !fits { return .red }
        if utilization > 0.8 { return .red }
        if utilization > 0.5 { return .yellow }
        return .green
    }

    var body: some View {
        VStack(spacing: 12) {
            // Top-down plate diagram
            GeometryReader { geometry in
                let maxWidth = geometry.size.width
                let maxHeight = min(geometry.size.height, maxWidth * 0.7)
                let scale = min(maxWidth / CGFloat(plateX), maxHeight / CGFloat(plateY))
                let plateW = CGFloat(plateX) * scale
                let plateH = CGFloat(plateY) * scale
                let modelW = min(CGFloat(modelX) * scale, plateW)
                let modelH = min(CGFloat(modelY) * scale, plateH)

                ZStack {
                    // Build plate outline
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.gray, lineWidth: 2)
                        .frame(width: plateW, height: plateH)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.fill.tertiary)
                        )

                    // FEP stress zone for resin printers (center 60%)
                    if isResinPrinter {
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.orange.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .frame(width: plateW * 0.6, height: plateH * 0.6)
                    }

                    // Model footprint
                    Rectangle()
                        .fill(utilizationColor.opacity(0.3))
                        .border(utilizationColor, width: 2)
                        .frame(width: modelW, height: modelH)

                    // Dimension labels on model
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f", modelX))
                            .font(.caption2)
                            .fontWeight(.bold)
                        Text("×")
                            .font(.caption2)
                        Text(String(format: "%.1f", modelY))
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                    .foregroundStyle(utilizationColor)
                }
                .frame(width: maxWidth, height: maxHeight)
            }
            .frame(height: 160)

            // Stats bar
            HStack(spacing: 16) {
                // Fit status
                HStack(spacing: 4) {
                    Image(systemName: fits ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(fits ? .green : .red)
                        .font(.caption)
                    Text(fits ? "Fits" : "Too Large")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(fits ? .green : .red)
                }

                // Area utilization
                HStack(spacing: 4) {
                    Image(systemName: "square.dashed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(Int(utilization * 100))% area")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Height utilization
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.and.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(Int(heightUtilization * 100))% height")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Build plate label
            HStack {
                Text("Build Plate: \(String(format: "%.0f × %.0f × %.0f mm", plateX, plateY, plateZ))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if isResinPrinter {
                    Text("FEP zone shown")
                        .font(.caption2)
                        .foregroundStyle(.orange.opacity(0.7))
                }
            }
        }
    }
}
