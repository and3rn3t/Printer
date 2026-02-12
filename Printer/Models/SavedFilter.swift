//
//  SavedFilter.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import Foundation
import SwiftData

/// A user-defined saved filter preset for quickly filtering the model library.
///
/// Combines tags, file type, size range, and favorites into a reusable filter.
@Model
final class SavedFilter {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdDate: Date

    /// Tags to filter by (models must have ALL of these tags)
    var tags: [String]

    /// File type filter (nil = any)
    var fileType: String?

    /// Minimum file size in bytes (nil = no minimum)
    var minFileSize: Int64?

    /// Maximum file size in bytes (nil = no maximum)
    var maxFileSize: Int64?

    /// Only show favorites
    var favoritesOnly: Bool

    /// Only show models needing slicing
    var needsSlicingOnly: Bool

    /// Only show sliced/print-ready models
    var printReadyOnly: Bool

    /// Icon name for display
    var icon: String

    init(
        name: String,
        tags: [String] = [],
        fileType: String? = nil,
        minFileSize: Int64? = nil,
        maxFileSize: Int64? = nil,
        favoritesOnly: Bool = false,
        needsSlicingOnly: Bool = false,
        printReadyOnly: Bool = false,
        icon: String = "line.3.horizontal.decrease.circle"
    ) {
        self.id = UUID()
        self.name = name
        self.createdDate = Date()
        self.tags = tags
        self.fileType = fileType
        self.minFileSize = minFileSize
        self.maxFileSize = maxFileSize
        self.favoritesOnly = favoritesOnly
        self.needsSlicingOnly = needsSlicingOnly
        self.printReadyOnly = printReadyOnly
        self.icon = icon
    }

    /// Test whether a model matches this filter
    func matches(_ model: PrintModel) -> Bool {
        // Tag filter: model must contain ALL filter tags
        if !tags.isEmpty {
            let modelTags = Set(model.tags.map { $0.lowercased() })
            let filterTags = Set(tags.map { $0.lowercased() })
            guard filterTags.isSubset(of: modelTags) else { return false }
        }

        // File type
        if let fileType, !fileType.isEmpty {
            guard model.fileType.rawValue == fileType else { return false }
        }

        // Size range
        if let min = minFileSize, model.fileSize < min { return false }
        if let max = maxFileSize, model.fileSize > max { return false }

        // Favorites
        if favoritesOnly && !model.isFavorite { return false }

        // Slicing status
        if needsSlicingOnly && !model.requiresSlicing { return false }
        if printReadyOnly && model.requiresSlicing { return false }

        return true
    }
}
