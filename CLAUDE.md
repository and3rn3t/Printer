# CLAUDE.md — Agent Instructions for Claude

## Project Overview

Printer is a SwiftUI 3D printing management app for Anycubic printers. Users import/scan 3D models (STL, OBJ, USDZ), convert between formats, manage a model library, discover and connect to printers over the local network, and control print jobs. This is a personal learning project (not monetized).

The developer owns an **Anycubic Photon Mono X 6K** resin printer (firmware V0.2.2) at `192.168.1.49:6000` using the ACT protocol.

## Tech Stack

- **Language**: Swift, targeting iOS 26.2 / macOS 26.2 / visionOS 26.2
- **UI**: SwiftUI (`NavigationSplitView`, sheets, forms)
- **Persistence**: SwiftData (`@Model`, `ModelContainer`, `@Query`)
- **3D Processing**: ModelIO + SceneKit (with `import SceneKit.ModelIO` for bridging)
- **Networking**: `NWConnection` (TCP for ACT protocol), `URLSession` (HTTP for OctoPrint/Anycubic HTTP)
- **Concurrency**: Swift actors for thread-safe services, structured concurrency throughout
- **Observation**: `@Observable` for discovery and network monitoring classes

## Project Structure

```
Printer/
  App/          — PrinterApp.swift (@main entry, ModelContainer setup)
  Models/       — SwiftData models: PrintModel, PrintJob, Printer, PrinterProtocol, enums
  Views/        — SwiftUI views (ContentView, ModelDetailView, PrintJobView, PrinterManagementView, ObjectScannerView)
  Services/     — Actor-based services:
                    AnycubicPrinterAPI  — unified printer API (delegates to PhotonPrinterService for ACT)
                    PhotonPrinterService — ACT protocol client (TCP port 6000 for Photon resin printers)
                    PrinterDiscovery    — Bonjour, subnet scan, ACT probing
                    STLFileManager      — file import/save/delete/validate
                    ModelConverter      — USDZ/OBJ/STL conversion
                    NetworkMonitor      — NWPathMonitor wrapper
  Resources/    — Info.plist, entitlements, Assets.xcassets
  Docs/         — Markdown documentation (ANYCUBIC_API.md, BUILD_FIXES.md, etc.)
```

## Data Models (Item.swift)

| Model | Key Properties |
|-------|---------------|
| `PrintModel` | `name`, `fileURL` (relative path), `resolvedFileURL` (computed), `fileSize`, `source`, `thumbnailData` (@Attribute(.externalStorage)), `printJobs` |
| `PrintJob` | `startDate`, `endDate`, `status` (PrintStatus enum), `printerName`, `model` |
| `Printer` | `name`, `ipAddress`, `port`, `printerProtocol` (PrinterProtocol enum), `apiKey`, `serialNumber`, `firmwareVersion` |
| `PrinterProtocol` | `.act` (TCP 6000), `.octoprint` (HTTP 80), `.anycubicHTTP` (HTTP 18910) |
| `ModelSource` | `.scanned`, `.imported`, `.downloaded` |
| `PrintStatus` | `.preparing`, `.uploading`, `.queued`, `.printing`, `.completed`, `.failed`, `.cancelled` |

## Printer Communication

### ACT Protocol (Photon Resin Printers)
- **Transport**: TCP port 6000
- **Format**: Send `command[,params]\r\n`, receive `command,values,...,end`
- **Service**: `PhotonPrinterService` actor
- **Commands**: `getstatus`, `sysinfo`, `getwifi`, `gopause`, `goresume`, `gostop`, `goprint,<filename>`
- **Errors**: `ERROR1` (not applicable), `ERROR2` (file not found)
- **Full reference**: `Printer/Docs/ANYCUBIC_API.md`

### OctoPrint / Anycubic HTTP (FDM Printers)
- **Transport**: HTTP REST (port 80 or 18910)
- **Service**: `AnycubicPrinterAPI` actor (direct URLSession calls)
- **Endpoints**: `/api/version`, `/api/printer`, `/api/job`, `/api/files/local`

### Unified API
`AnycubicPrinterAPI` is the single entry point. Methods accept a `protocol` parameter:
- `.act` → delegates to `PhotonPrinterService`
- `.octoprint` / `.anycubicHTTP` → uses HTTP directly

## Architecture & Patterns

- Service classes are **Swift `actor`** types for concurrency safety
- Data models use **SwiftData `@Model`** with `@Relationship(deleteRule: .cascade)` and `@Attribute(.unique)` on IDs
- File paths stored as **relative paths** (survive container changes); resolved via `resolvedFileURL` computed property
- Views use `@Query` for declarative data fetching and `@Environment(\.modelContext)` for mutations
- Error handling uses **`LocalizedError`-conforming enums** with `.alert()` modifiers in views (no `print()` for user-facing errors)
- Printer discovery uses `@Observable` (`PrinterDiscovery`) with Bonjour + ACT probing + subnet scanning
- Cross-platform support via `#if os(iOS)` / `#if os(macOS)` conditionals

## Code Conventions

- Use `// MARK: - Section Name` to organize code sections
- Add `///` doc comments on all public types, properties, and methods
- Use `final class` for all `@Model` types
- Use descriptive names — no abbreviations (e.g., `PrintModel`, not `PM`)
- Standard Apple file headers with creator name and date
- Default parameter values in initializers where sensible
- Codable enums for status/source types
- Surface errors to users via `.alert()` modifiers, not `print()` statements

## Platform-Specific Rules

The app targets iOS, macOS, and visionOS simultaneously. Follow these rules strictly:

- **Never use** `Color(.systemGray6)` — use `Color.gray.opacity(0.15)` instead
- **Guard iOS-only modifiers** with `#if os(iOS)`:
  - `.navigationBarTitleDisplayMode(.inline)`
  - `.keyboardType(.decimalPad)`
  - `.textContentType(.none)`
- **Guard macOS-only APIs** with `#if os(macOS)`:
  - `NSImage`, `.tiffRepresentation`
- **Guard iOS-only APIs** with `#if os(iOS)`:
  - `UIImage`
- When using `SCNScene(mdlAsset:)` or similar bridging, always `import SceneKit.ModelIO`

## Build Commands

```bash
# Build
xcodebuild -project Printer.xcodeproj -scheme Printer build

# Check for errors only
xcodebuild -project Printer.xcodeproj -scheme Printer build 2>&1 | grep "error:"

# Clean build
xcodebuild -project Printer.xcodeproj -scheme Printer clean build

# Run tests
xcodebuild -project Printer.xcodeproj -scheme Printer test
```

## Key Files

| File | Purpose |
|------|---------|
| `Printer/Models/Item.swift` | All SwiftData model definitions + enums |
| `Printer/Services/AnycubicPrinterAPI.swift` | Unified printer API with retry logic |
| `Printer/Services/PhotonPrinterService.swift` | ACT protocol TCP client for Photon printers |
| `Printer/Services/PrinterDiscovery.swift` | Network discovery (Bonjour + ACT + subnet) |
| `Printer/Services/STLFileManager.swift` | File I/O with relative path support |
| `Printer/Views/ContentView.swift` | Main app navigation and model list |
| `Printer/Views/PrinterManagementView.swift` | Printer management, discovery, detail/controls |
| `Printer/App/PrinterApp.swift` | App entry point and ModelContainer setup |
| `Printer/Docs/ANYCUBIC_API.md` | ACT protocol reference |

## File Placement

When creating new files:
- SwiftUI views → `Printer/Views/`
- Data models → `Printer/Models/`
- Networking/file/conversion logic → `Printer/Services/`
- App lifecycle → `Printer/App/`
- Documentation → `Printer/Docs/`

## Important Notes

- The Xcode project uses `PBXFileSystemSynchronizedRootGroup` — new files placed under `Printer/` are auto-detected
- `INFOPLIST_FILE` path is `Printer/Resources/Info.plist`
- Always verify builds after changes: `xcodebuild -project Printer.xcodeproj -scheme Printer build 2>&1 | grep "error:"`
- Photon resin printers cannot print raw STL files — they need sliced formats (`.pwmx`, `.pwma`)
- The app stores file paths as relative (not absolute) to survive container/reinstall changes
