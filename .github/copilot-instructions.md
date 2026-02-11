# Copilot Instructions

## Project Context
This is a Swift/SwiftUI 3D printing management app for Anycubic printers. It supports iOS 26.2, macOS 26.2, and visionOS 26.2. Users can import 3D models (STL, OBJ, USDZ), convert formats, manage a model library, connect to printers, and track print jobs.

## Architecture
- **SwiftData** for persistence with `@Model` classes (`PrintModel`, `PrintJob`, `Printer`)
- **Swift actors** for services (`AnycubicPrinterAPI`, `ModelConverter`, `STLFileManager`)
- **SwiftUI** with `NavigationSplitView`, `@Query`, `@Environment(\.modelContext)`
- **ModelIO + SceneKit** for 3D file processing (always include `import SceneKit.ModelIO` when using bridging APIs)
- **async/await** structured concurrency throughout

## Project Structure
- `Printer/App/` — App entry point (`@main`)
- `Printer/Models/` — SwiftData `@Model` classes and enums
- `Printer/Views/` — SwiftUI views
- `Printer/Services/` — Actor-based networking, file management, format conversion
- `Printer/Resources/` — Info.plist, entitlements, asset catalog
- `Printer/Docs/` — Documentation

## Code Style
- Use `// MARK: - Section Name` for code organization
- Add `///` doc comments on public APIs
- Use `final class` for `@Model` types
- Use descriptive names, no abbreviations
- Use `LocalizedError`-conforming enums for error handling
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

## File Placement
When creating new files:
- SwiftUI views → `Printer/Views/`
- Data models → `Printer/Models/`
- Networking/file/conversion logic → `Printer/Services/`
- App lifecycle → `Printer/App/`

## Build Verification
After making changes, verify the build:
```bash
xcodebuild -project Printer.xcodeproj -scheme Printer build 2>&1 | grep "error:"
```
