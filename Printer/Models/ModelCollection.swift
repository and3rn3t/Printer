//
//  ModelCollection.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import Foundation
import SwiftData

/// A named collection for organizing `PrintModel`s into groups.
///
/// Users can create collections like "Miniatures", "Phone Cases",
/// or "Client Orders" to organize their model library.
@Model
final class ModelCollection {
    @Attribute(.unique) var id: UUID
    var name: String
    var icon: String
    var colorHex: String
    var createdDate: Date
    var modifiedDate: Date

    /// Models in this collection (many-to-many via inverse on PrintModel)
    @Relationship(inverse: \PrintModel.collections)
    var models: [PrintModel]

    init(
        name: String,
        icon: String = "folder.fill",
        colorHex: String = "007AFF"
    ) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.createdDate = Date()
        self.modifiedDate = Date()
        self.models = []
    }
}
