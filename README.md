# Printer

A SwiftUI 3D printing management app for Anycubic printers. Import 3D models, discover printers on your network, and manage print jobs — all from iOS, macOS, or visionOS.

> **Personal learning project** — not monetized. Built to explore SwiftUI, SwiftData, networking protocols, and 3D graphics.

## Features

### Model Library
- Import STL, OBJ, and USDZ files with automatic thumbnail generation
- Convert between formats using ModelIO + SceneKit
- Organize models into collections with tags
- Mesh analysis (triangle count, bounding box, manifold checks)
- Notes, metadata, and search/filter with saved filters

### 3D Object Scanning
- Scan real-world objects with LiDAR via Object Capture Kit (iOS only)
- Guided workflow with recommended third-party scanning apps

### Printer Management
- Discover Anycubic printers via Bonjour, ACT protocol probing (TCP 6000), and subnet scanning
- Connect, monitor status, pause/resume/cancel print jobs
- Browse and manage files on printer storage
- Live webcam streaming for supported printers
- Build plate visualization and temperature charts

### Multi-Protocol Support
| Protocol | Transport | Port | Printers |
|----------|-----------|------|----------|
| **ACT** | TCP | 6000 | Photon Mono X 6K and other Photon resin printers |
| **OctoPrint** | HTTP REST | 80 | FDM printers running OctoPrint firmware |
| **Anycubic HTTP** | HTTP | 18910 | Older Anycubic FDM printers |

### Print Workflow
- Upload models to printers with progress tracking
- Print queue management
- Full print history with status tracking
- Photo log for documenting print results and failures
- Failure annotation for tracking and learning from issues
- Cost analytics (resin/filament usage, per-print cost)

### Printables Integration
- Browse and search models on Printables.com
- View model details, images, and metadata
- Download models directly into the library

### Dashboard & Analytics
- At-a-glance printer status and recent activity
- Print statistics and success rates
- Cost tracking and analytics charts

### Inventory & Maintenance
- Track resin/filament inventory with usage history
- Resin profiles with exposure settings
- Maintenance event logging and scheduling
- Scheduled maintenance reminders

### Widgets & Shortcuts
- Home Screen widget showing printer status
- Live Activity for active print jobs
- Siri Shortcuts for common actions (check status, start print)

### Data Management
- iCloud sync via CloudKit
- Export/import library data
- Background print monitoring with notifications

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
2. Tap **+** to add a printer manually, or use **Find Printers** to scan your subnet
3. Enter the printer's name and IP address
4. Tap **Test Connection** to verify, then **Add**

## Architecture

```
Printer/
├── App/
│   └── PrinterApp.swift              @main entry, ModelContainer setup
├── Models/
│   ├── Item.swift                    PrintModel, PrintJob, Printer, enums
│   ├── ModelCollection.swift         Collection/tag organization
│   ├── InventoryItem.swift           Resin/filament inventory
│   ├── MaintenanceEvent.swift        Printer maintenance records
│   ├── ResinProfile.swift            Resin exposure profiles
│   ├── PrintPhotoLog.swift           Photo documentation of prints
│   ├── PrintablesModels.swift        Printables.com data types
│   ├── PrintActivityAttributes.swift Live Activity attributes
│   └── SavedFilter.swift             Persisted search filters
├── Views/
│   ├── ContentView.swift             Main NavigationSplitView + model list
│   ├── DashboardView.swift           Overview dashboard
│   ├── ModelDetailView.swift         3D model detail + metadata
│   ├── PrintJobView.swift            Upload workflow with progress
│   ├── PrinterManagementView.swift   Printer list, discovery, controls
│   ├── PrinterDetailView.swift       Single printer detail + real-time status
│   ├── EditPrinterView.swift         Add/edit printer form
│   ├── PrinterFileBrowserView.swift  Browse files on printer storage
│   ├── ObjectScannerView.swift       LiDAR object capture (iOS only)
│   ├── CollectionManagementView.swift Model collections + tags
│   ├── PrintHistoryView.swift        Print job history
│   ├── PrintQueueView.swift          Print queue management
│   ├── CostAnalyticsView.swift       Cost tracking + charts
│   ├── StatisticsView.swift          Print statistics overview
│   ├── InventoryView.swift           Resin/filament inventory
│   ├── ResinProfileView.swift        Resin profile management
│   ├── MaintenanceLogView.swift      Maintenance event log
│   ├── PhotoLogView.swift            Print photo documentation
│   ├── FailureAnnotationView.swift   Annotate print failures
│   ├── PrintablesBrowseView.swift    Browse Printables.com
│   ├── PrintablesDetailView.swift    Printables model detail
│   ├── TagBrowserView.swift          Browse models by tag
│   ├── SettingsView.swift            App settings
│   ├── ShareSheetView.swift          Share/export models
│   └── Components/
│       ├── BuildPlateView.swift      Build plate visualization
│       ├── FlowLayout.swift          Tag flow layout
│       ├── Model3DPreviewView.swift  3D model SceneKit preview
│       ├── StatusDisplayHelpers.swift Status badge/label helpers
│       ├── TemperatureChartView.swift Temperature chart
│       └── WebcamStreamView.swift    Live webcam stream
├── Services/
│   ├── AnycubicPrinterAPI.swift      Unified printer API (ACT + OctoPrint + HTTP)
│   ├── PhotonPrinterService.swift    ACT protocol TCP client (port 6000)
│   ├── PrinterDiscovery.swift        Bonjour + subnet scanning + ACT probing
│   ├── PrinterConnectionManager.swift Connection state management
│   ├── STLFileManager.swift          File import/save/delete/validate
│   ├── ModelConverter.swift          USDZ/OBJ/STL format conversion
│   ├── MeshAnalyzer.swift            Triangle count, bounds, manifold checks
│   ├── SlicedFileParser.swift        Parse sliced file metadata (.pwmx, etc.)
│   ├── NetworkMonitor.swift          NWPathMonitor wrapper
│   ├── PrintablesService.swift       Printables.com API client
│   ├── CloudSyncManager.swift        iCloud/CloudKit sync
│   ├── ExportService.swift           Library export/import
│   ├── BackgroundPrintMonitor.swift  Background print status polling
│   ├── PrintNotificationManager.swift Local notification scheduling
│   ├── PrintActivityManager.swift    Live Activity management
│   ├── MaintenanceScheduler.swift    Maintenance reminder scheduling
│   ├── TimelapseCapture.swift        Print timelapse capture
│   └── WidgetSharedData.swift        Shared data for widget extension
├── Intents/
│   ├── PrinterEntity.swift           App Entity for Shortcuts
│   ├── PrinterIntents.swift          Siri Shortcut intents
│   └── PrinterShortcuts.swift        Shortcut definitions
├── Resources/
│   ├── Info.plist                    App configuration
│   ├── Printer.entitlements          Capabilities
│   └── Assets.xcassets/              Images and colors
└── Docs/
    ├── ANYCUBIC_API.md               ACT protocol reference
    ├── PHOTON_PROTOCOL_RESEARCH.md   Multi-protocol research (CBD, ACT, SDCP V3)
    └── INFO_PLIST_SETUP.md           Required Info.plist entries

widget/                               WidgetKit extension
├── PrinterWidgetBundle.swift         Widget bundle entry point
├── PrinterStatusWidget.swift         Home Screen status widget
├── PrinterLiveActivity.swift         Live Activity for active prints
├── PrintActivityAttributes.swift     Shared activity attributes
└── WidgetSharedData.swift            Shared data bridge
```

### Key Patterns

| Pattern | Usage |
|---------|-------|
| **SwiftData** | `@Model` classes (`PrintModel`, `PrintJob`, `Printer`, etc.), `@Query`, `@Environment(\.modelContext)` |
| **Swift Actors** | `AnycubicPrinterAPI`, `PhotonPrinterService`, `ModelConverter`, `STLFileManager`, and other services |
| **@Observable** | `PrinterDiscovery`, `NetworkMonitor` |
| **async/await** | Structured concurrency throughout all network and file I/O |
| **NavigationSplitView** | Adaptive layout for iPhone / iPad / Mac / visionOS |
| **WidgetKit** | Home Screen widget + Live Activity |
| **App Intents** | Siri Shortcuts for printer control |

### Data Models

| Model | Purpose |
|-------|---------|
| `PrintModel` | 3D model with relative file path, metadata, thumbnail, collections, print history |
| `PrintJob` | Print job record with status tracking (preparing → printing → completed) |
| `Printer` | Saved printer with IP, port, protocol, serial, firmware version |
| `ModelCollection` | Named collection for organizing models with tags |
| `InventoryItem` | Resin/filament inventory tracking |
| `ResinProfile` | Resin exposure settings per material |
| `MaintenanceEvent` | Printer maintenance log entries |
| `PrintPhotoLog` | Photo documentation of print results |
| `SavedFilter` | Persisted search/filter configurations |

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
| [PHOTON_PROTOCOL_RESEARCH.md](Printer/Docs/PHOTON_PROTOCOL_RESEARCH.md) | Comprehensive multi-protocol research (CBD, ACT, SDCP V3) |
| [INFO_PLIST_SETUP.md](Printer/Docs/INFO_PLIST_SETUP.md) | Required Info.plist entries for permissions and file types |

## License

Personal project — no license specified.
