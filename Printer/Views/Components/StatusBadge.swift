//
//  StatusBadge.swift
//  Printer
//
//  Created by Matt on 2/12/26.
//

import SwiftUI

// MARK: - Status Badge

/// A reusable capsule badge for displaying status labels with consistent iOS 26 HIG styling.
///
/// Uses semantic `.fill.tertiary` backgrounds with tinted foreground colors for
/// system-consistent appearance across light/dark modes and accessibility settings.
struct StatusBadge: View {
    let text: String
    let color: Color
    var icon: String?
    var size: BadgeSize = .regular

    enum BadgeSize {
        case small
        case regular

        var font: Font {
            switch self {
            case .small: return .caption2
            case .regular: return .caption
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .small: return 6
            case .regular: return 8
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .small: return 3
            case .regular: return 4
            }
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(size == .small ? .caption2 : .caption)
            }
            Text(text)
        }
        .font(size.font)
        .fontWeight(.semibold)
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .foregroundStyle(color)
        .background(color.opacity(0.12), in: .capsule)
    }
}

// MARK: - Convenience Initializers

extension StatusBadge {
    /// Create a badge from a `PrintStatus` value.
    init(status: PrintStatus) {
        self.text = status.displayText
        self.color = status.color
        self.icon = nil
    }
}

#Preview {
    VStack(spacing: 12) {
        StatusBadge(text: "Completed", color: .green, icon: "checkmark.circle.fill")
        StatusBadge(text: "Failed", color: .red)
        StatusBadge(text: "Printing", color: .blue, size: .small)
        StatusBadge(text: "STL", color: .orange, size: .small)
    }
    .padding()
}
