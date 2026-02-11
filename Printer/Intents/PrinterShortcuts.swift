//
//  PrinterShortcuts.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import AppIntents

/// Registers App Shortcuts with Siri phrase triggers.
struct PrinterShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckPrinterStatusIntent(),
            phrases: [
                "Check printer status in \(.applicationName)",
                "What's my printer doing in \(.applicationName)",
                "Printer status \(.applicationName)"
            ],
            shortTitle: "Check Printer Status",
            systemImageName: "printer"
        )

        AppShortcut(
            intent: GetPrintProgressIntent(),
            phrases: [
                "Get print progress in \(.applicationName)",
                "How's my print going in \(.applicationName)",
                "Print progress \(.applicationName)"
            ],
            shortTitle: "Print Progress",
            systemImageName: "gauge.with.dots.needle.33percent"
        )

        AppShortcut(
            intent: GetModelCountIntent(),
            phrases: [
                "How many models in \(.applicationName)",
                "Model count in \(.applicationName)",
                "Count my 3D models in \(.applicationName)"
            ],
            shortTitle: "Model Count",
            systemImageName: "cube.fill"
        )

        AppShortcut(
            intent: GetPrintStatsIntent(),
            phrases: [
                "Get print stats in \(.applicationName)",
                "My printing statistics in \(.applicationName)",
                "Print success rate in \(.applicationName)"
            ],
            shortTitle: "Print Statistics",
            systemImageName: "chart.bar.fill"
        )

        AppShortcut(
            intent: ListPrintersIntent(),
            phrases: [
                "List my printers in \(.applicationName)",
                "Show my 3D printers in \(.applicationName)",
                "What printers do I have in \(.applicationName)"
            ],
            shortTitle: "List Printers",
            systemImageName: "list.bullet"
        )
    }
}
