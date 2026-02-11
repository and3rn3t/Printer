# Printer

A SwiftUI 3D printing management app for Anycubic printers. Import 3D models, discover printers on your network, and manage print jobs — all from iOS, macOS, or visionOS.

> **Personal learning project** — not monetized. Built to explore SwiftUI, SwiftData, networking protocols, and 3D graphics.

## Features

- **Model Library** — Import STL, OBJ, and USDZ files. SwiftData persistence with thumbnails and metadata.
- **3D Object Scanning** — Scan real-world objects with LiDAR via Object Capture Kit (iOS only).
- **Format Conversion** — Convert between USDZ, OBJ, and STL using ModelIO + SceneKit.
- **Printer Discovery** — Find Anycubic printers on your LAN via Bonjour, ACT protocol probing (TCP 6000), and subnet scanning.
- **Printer Control** — Connect, monitor status, pause/resume/cancel print jobs.
- **Multi-Protocol** — Supports Anycubic ACT protocol (Photon resin printers), OctoPrint REST API (FDM), and Anycubic HTTP (port 18910).

## Requirements

| Platform | Minimum Version |
|----------|----------------|
| iOS / iPadOS | 26.2 |
| macOS | 26.2 |
| visionOS | 26.2 |

- **LiDAR sensor** required for 3D scanning (iPhone 12 Pro+, iPad Pro 2020+)
- **Local network** access required for printer communication

## Getting Started

### 1. Clone & Open

```bash
git clone https://github.com/and3rn3t/Printer.git
cd Printer
open Printer.xcodeproj
```

### 2. Build

```bash
xcodebuild -project Printer.xcodeproj -scheme Printer build
```

Or press ⌘B in Xcode.

### 3. Run

Select a destination (iPhone, Mac, or visionOS Simulator) and press ⌘R.

### 4. Connect a Printer

1. Open the app → tap the printer icon in the toolbar
2. Tap **+** to add a printer
3. Enter the printer's name and IP address
4. Tap **Test Connection** to verify
5. Tap **Add**

Or use **Find Printers** to scan your subnet automatically.

## Architecture

```
Printer/
├── App/            PrinterApp.swift — @main entry, ModelContainer setup
├── Models/         SwiftData @Model classes and Codable enums
│   └── Item.swift  PrintModel, PrintJob, Printer, PrinterProtocol, etc.
├── Views/          SwiftUI views
│   ├── ContentView.swift           Main NavigationSplitView + model list
│   ├── ModelDetailView.swift       3D model detail + metadata
│   ├── PrintJobView.swift          Upload workflow with progress
│   ├── PrinterManagementView.swift Printer list, discovery, detail + controls
│   └── ObjectScannerView.swift     LiDAR object capture (iOS only)
├── Services/       Actor-based business logic
│   ├── AnycubicPrinterAPI.swift    Unified printer API (ACT + OctoPrint + HTTP)
│   ├── PhotonPrinterService.swift  ACT protocol client (TCP port 6000)
│   ├── PrinterDiscovery.swift      Bonjour + subnet scanning + ACT probing
│   ├── STLFileManager.swift        File import/save/delete/validate
│   ├── ModelConverter.swift        USDZ/OBJ/STL format conversion
│   └── NetworkMonitor.swift        NWPathMonitor wrapper
├── Resources/      Info.plist, entitlements, asset catalog
└── Docs/           Protocol docs, build guides, architecture notes
```

### Key Patterns

| Pattern | Usage |
|---------|-------|
| **SwiftData** | `@Model` classes (`PrintModel`, `PrintJob`, `Printer`), `@Query`, `@Environment(\.modelContext)` |
| **Swift Actors** | `AnycubicPrinterAPI`, `PhotonPrinterService`, `ModelConverter`, `STLFileManager` |
| **@Observable** | `PrinterDiscovery`, `NetworkMonitor` |
| **async/await** | Structured concurrency throughout all network and file I/O |
| **NavigationSplitView** | Adaptive layout for iPhone / iPad / Mac / visionOS |

### Data Models

| Model | Purpose |
|-------|---------|
| `PrintModel` | 3D model with relative file path, metadata, thumbnail, print history |
| `PrintJob` | Print job record with status tracking (preparing → printing → completed) |
| `Printer` | Saved printer with IP, port, protocol, serial, firmware version |
| `PrinterProtocol` | `.act` (Photon TCP), `.octoprint` (FDM HTTP), `.anycubicHTTP` (port 18910) |

### Printer Communication

The app supports three protocols:

| Protocol | Transport | Port | Printers |
|----------|-----------|------|----------|
| **ACT** | TCP | 6000 | Photon Mono X 6K and other Photon resin printers |
| **OctoPrint** | HTTP REST | 80 | FDM printers running OctoPrint firmware |
| **Anycubic HTTP** | HTTP | 18910 | Older Anycubic FDM printers |

`AnycubicPrinterAPI` is the unified entry point — it delegates to `PhotonPrinterService` for ACT printers and uses `URLSession` for HTTP printers.

See [Printer/Docs/ANYCUBIC_API.md](Printer/Docs/ANYCUBIC_API.md) for the full ACT protocol reference.

## Cross-Platform

The app compiles for iOS, macOS, and visionOS from a single codebase. Platform-specific APIs are guarded:

```swift
#if os(iOS)
.navigationBarTitleDisplayMode(.inline)
.keyboardType(.decimalPad)
#endif
```

**Rules:**
- Never use `Color(.systemGray6)` — use `Color.gray.opacity(0.15)`
- Guard `UIImage` with `#if os(iOS)`, `NSImage` with `#if os(macOS)`
- Always `import SceneKit.ModelIO` when using ModelIO↔SceneKit bridging

## Testing

```bash
xcodebuild -project Printer.xcodeproj -scheme Printer test
```

Test files live in `PrinterTests/` and `PrinterUITests/`.

## Documentation

| Document | Description |
|----------|-------------|
| [ANYCUBIC_API.md](Printer/Docs/ANYCUBIC_API.md) | ACT protocol reference (reverse-engineered from Photon Mono X 6K) |
| [BUILD_FIXES.md](Printer/Docs/BUILD_FIXES.md) | Common build issue resolutions |
| [INFO_PLIST_SETUP.md](Printer/Docs/INFO_PLIST_SETUP.md) | Required Info.plist entries |
| [QUICK_START.md](Printer/Docs/QUICK_START.md) | Quick start guide |

## Roadmap

This project follows a weekly cadence. Current progress:

- [x] **Phase 1 — Foundation** (Weeks 1–4): Info.plist, file stability, error surfacing, printer handshake, unit tests
- [ ] **Phase 2 — Online Model Library** (Weeks 5–11): Printables.com integration, download manager, library organization
- [ ] **Phase 3 — 3D Graphics** (Weeks 13–22): Interactive viewer, mesh analysis, thumbnail improvements
- [ ] **Phase 4 — Polish** (Weeks 23+): Widget, Shortcuts, Spotlight, accessibility

## License

Personal project — no license specified.
