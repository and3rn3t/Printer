# Copilot Instructions

## Project Context
This is a Swift/SwiftUI 3D printing management app for Anycubic printers. It supports iOS 26.2, macOS 26.2, and visionOS 26.2. Users can import 3D models (STL, OBJ, USDZ), convert formats, manage a model library, discover and connect to printers, and control print jobs. Personal learning project, not monetized.

The developer's printer is an **Anycubic Photon Mono X 6K** (resin, firmware V0.2.2) at `192.168.1.49:6000` using the ACT protocol.

## Architecture
- **SwiftData** for persistence with `@Model` classes (`PrintModel`, `PrintJob`, `Printer`)
- **Swift actors** for services (`AnycubicPrinterAPI`, `PhotonPrinterService`, `ModelConverter`, `STLFileManager`)
- **SwiftUI** with `NavigationSplitView`, `@Query`, `@Environment(\.modelContext)`
- **ModelIO + SceneKit** for 3D file processing (always include `import SceneKit.ModelIO` when using bridging APIs)
- **NWConnection** for TCP communication (ACT protocol on port 6000)
- **URLSession** for HTTP communication (OctoPrint on port 80, Anycubic HTTP on port 18910)
- **@Observable** for `PrinterDiscovery` and `NetworkMonitor`
- **async/await** structured concurrency throughout

## Project Structure
- `Printer/App/` — App entry point (`@main`, ModelContainer setup)
- `Printer/Models/` — SwiftData `@Model` classes and Codable enums
- `Printer/Views/` — SwiftUI views (ContentView, ModelDetailView, PrintJobView, PrinterManagementView, ObjectScannerView)
- `Printer/Services/` — Actor-based networking, file management, format conversion, printer discovery
- `Printer/Resources/` — Info.plist, entitlements, asset catalog
- `Printer/Docs/` — Documentation (ANYCUBIC_API.md, BUILD_FIXES.md, etc.)

## Data Models (Item.swift)
- `PrintModel` — 3D model with relative file path (`fileURL`), `resolvedFileURL` computed property, `@Attribute(.externalStorage)` on `thumbnailData`
- `PrintJob` — Print job with `PrintStatus` enum (preparing/uploading/queued/printing/completed/failed/cancelled)
- `Printer` — Saved printer with IP, port, `printerProtocol` (`PrinterProtocol` enum: `.act`, `.octoprint`, `.anycubicHTTP`)
- File paths are stored as **relative paths** to survive container/reinstall changes

## Printer Protocols
- **ACT** (TCP 6000) — Photon resin printers. `PhotonPrinterService` actor. Commands: `getstatus`, `sysinfo`, `getwifi`, `gopause`/`goresume`/`gostop`, `goprint,<filename>`. See `Printer/Docs/ANYCUBIC_API.md`.
- **OctoPrint** (HTTP 80) — FDM printers. REST API via `AnycubicPrinterAPI` actor.
- **Anycubic HTTP** (port 18910) — Older Anycubic FDM printers. JSON endpoint at `/info`.
- `AnycubicPrinterAPI` is the unified entry point — delegates ACT calls to `PhotonPrinterService`.

## Code Style
- Use `// MARK: - Section Name` for code organization
- Add `///` doc comments on public APIs
- Use `final class` for `@Model` types
- Use descriptive names, no abbreviations
- Use `LocalizedError`-conforming enums for error handling
- Surface errors to users via `.alert()` modifiers, not `print()` statements
- Include standard Apple file headers

## Cross-Platform Rules
This app compiles for iOS, macOS, and visionOS. Follow these rules strictly:

- **Never use** `Color(.systemGray6)` — use `Color.gray.opacity(0.15)` instead
- **Guard iOS-only modifiers** with `#if os(iOS)`:
  - `.navigationBarTitleDisplayMode(_:)`
  - `.keyboardType(_:)`
  - `.textContentType(_:)`
- **Guard macOS-only APIs** with `#if os(macOS)`:
  - `NSImage`, `.tiffRepresentation`
- **Guard iOS-only APIs** with `#if os(iOS)`:
  - `UIImage`
- When using `SCNScene(mdlAsset:)` or similar bridging, always `import SceneKit.ModelIO`

## Key Files
| File | Purpose |
|------|---------|
| `Printer/Models/Item.swift` | All SwiftData models + enums |
| `Printer/Services/AnycubicPrinterAPI.swift` | Unified printer API with retry logic |
| `Printer/Services/PhotonPrinterService.swift` | ACT protocol TCP client |
| `Printer/Services/PrinterDiscovery.swift` | Bonjour + ACT probing + subnet scanning |
| `Printer/Views/ContentView.swift` | Main navigation and model list |
| `Printer/Views/PrinterManagementView.swift` | Printer list, discovery, detail/controls |

## File Placement
When creating new files:
- SwiftUI views → `Printer/Views/`
- Data models → `Printer/Models/`
- Networking/file/conversion logic → `Printer/Services/`
- App lifecycle → `Printer/App/`
- Documentation → `Printer/Docs/`

## Important Notes
- Xcode project uses `PBXFileSystemSynchronizedRootGroup` — new files under `Printer/` auto-detected
- Photon resin printers cannot print raw STL — they need sliced formats (`.pwmx`, `.pwma`)
- `INFOPLIST_FILE` = `Printer/Resources/Info.plist`

## Build Verification
After making changes, verify the build:
```bash
xcodebuild -project Printer.xcodeproj -scheme Printer build 2>&1 | grep "error:"
```
