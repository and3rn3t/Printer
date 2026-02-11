# CLAUDE.md — Agent Instructions for Claude

## Project Overview

Printer is a 3D printing management app for Anycubic printers. It lets users import/scan 3D models (STL, OBJ, USDZ), convert between formats, manage a model library, connect to printers over the network, and track print jobs.

## Tech Stack

- **Language**: Swift 5, targeting iOS 26.2 / macOS 26.2 / visionOS 26.2
- **UI**: SwiftUI (NavigationSplitView, sheets, forms)
- **Persistence**: SwiftData (`@Model`, `ModelContainer`, `@Query`)
- **3D Processing**: ModelIO + SceneKit (with `import SceneKit.ModelIO` for bridging)
- **Networking**: URLSession with async/await
- **Concurrency**: Swift actors for thread-safe services, structured concurrency throughout

## Project Structure

```
Printer/
  App/          — PrinterApp.swift (@main entry, ModelContainer setup)
  Models/       — SwiftData models: PrintModel, PrintJob, Printer, enums
  Views/        — SwiftUI views (ContentView, ModelDetailView, PrintJobView, etc.)
  Services/     — Actor-based services (AnycubicPrinterAPI, ModelConverter, STLFileManager)
  Resources/    — Info.plist, entitlements, Assets.xcassets
  Docs/         — Markdown documentation
```

## Architecture & Patterns

- Service classes are **Swift `actor`** types for concurrency safety
- Data models use **SwiftData `@Model`** with `@Relationship(deleteRule: .cascade)` and `@Attribute(.unique)` on IDs
- Views use `@Query` for declarative data fetching and `@Environment(\.modelContext)` for mutations
- Error handling uses **`LocalizedError`-conforming enums** with exhaustive `errorDescription` switches
- Cross-platform support via `#if os(iOS)` / `#if os(macOS)` conditionals

## Code Conventions

- Use `// MARK: - Section Name` to organize code sections
- Add `///` doc comments on all public types, properties, and methods
- Use `final class` for all `@Model` types
- Use descriptive names — no abbreviations (e.g., `PrintModel`, not `PM`)
- Standard Apple file headers with creator name and date
- Default parameter values in initializers where sensible
- Codable enums for status/source types

## Platform-Specific Considerations

- The app targets iOS, macOS, and visionOS simultaneously
- Use `#if os(iOS)` guards for iOS-only APIs:
  - `.navigationBarTitleDisplayMode(.inline)`
  - `.keyboardType(.decimalPad)`
  - `.textContentType(.none)`
- Use `#if os(macOS)` for macOS-specific rendering (e.g., `NSImage`, `.tiffRepresentation`)
- Avoid `Color(.systemGray6)` — it's iOS-only. Use `Color.gray.opacity(0.15)` instead
- SceneKit ModelIO bridging requires `import SceneKit.ModelIO` explicitly

## Build Commands

```bash
# Build
xcodebuild -project Printer.xcodeproj -scheme Printer build

# Clean build
xcodebuild -project Printer.xcodeproj -scheme Printer clean build

# Run tests
xcodebuild -project Printer.xcodeproj -scheme Printer test
```

## Key Files

- `Printer/Models/Item.swift` — All SwiftData model definitions
- `Printer/Services/AnycubicPrinterAPI.swift` — Printer network communication
- `Printer/Views/ContentView.swift` — Main app navigation and model list
- `Printer/App/PrinterApp.swift` — App entry point and container setup

## Important Notes

- The Xcode project uses `PBXFileSystemSynchronizedRootGroup` — file additions/moves are auto-detected by Xcode
- `INFOPLIST_FILE` path is `Printer/Resources/Info.plist`
- When adding new files, place them in the appropriate subfolder (Views/, Services/, Models/)
- Always verify builds after changes: `xcodebuild -project Printer.xcodeproj -scheme Printer build 2>&1 | grep "error:"`
