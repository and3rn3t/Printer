//
//  PrinterEntity.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import AppIntents
import SwiftData

// MARK: - Printer Entity

/// AppEntity representing a 3D printer for use in App Intents and Siri Shortcuts.
struct PrinterEntity: AppEntity {
    static var defaultQuery = PrinterEntityQuery()
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Printer"

    var id: UUID
    var name: String
    var ipAddress: String
    var printerProtocol: String
    var manufacturer: String
    var model: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(manufacturer) \(model)"
        )
    }
}

// MARK: - Printer Entity Query

struct PrinterEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [PrinterEntity] {
        let container = try ModelContainer(
            for: Printer.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: false)
        )
        let context = ModelContext(container)
        let allPrinters = try context.fetch(FetchDescriptor<Printer>())

        return allPrinters
            .filter { identifiers.contains($0.id) }
            .map { printer in
                PrinterEntity(
                    id: printer.id,
                    name: printer.name,
                    ipAddress: printer.ipAddress,
                    printerProtocol: printer.printerProtocol.rawValue,
                    manufacturer: printer.manufacturer,
                    model: printer.model
                )
            }
    }

    func suggestedEntities() async throws -> [PrinterEntity] {
        let container = try ModelContainer(
            for: Printer.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: false)
        )
        let context = ModelContext(container)
        let allPrinters = try context.fetch(FetchDescriptor<Printer>())

        return allPrinters.map { printer in
            PrinterEntity(
                id: printer.id,
                name: printer.name,
                ipAddress: printer.ipAddress,
                printerProtocol: printer.printerProtocol.rawValue,
                manufacturer: printer.manufacturer,
                model: printer.model
            )
        }
    }
}
