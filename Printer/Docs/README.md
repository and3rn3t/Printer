# 3D Printer App - Project Overview

## Features Implemented

### 1. 3D Object Scanning
- Uses Object Capture Kit on iOS devices with LiDAR
- Scans real-world objects and converts them to 3D models
- Automatically generates thumbnails for visual reference
- Supports conversion from USDZ (Object Capture output) to STL format

### 2. File Management
- Import STL files from Files app
- Import and convert OBJ and USDZ files
- Store files in app's Documents directory
- Track file metadata (size, creation date, source)
- SwiftData persistence for model library

### 3. Printer Integration
- Connect to Anycubic printers via IP address
- Test printer connectivity
- Upload STL files to printer
- Monitor print job status
- Manage multiple printers

### 4. User Interface
- Split view interface (works on iPhone, iPad, and Mac)
- Model library with thumbnails
- Detailed model view with metadata
- Printer management interface
- Print job history

## Architecture

### SwiftData Models
- **PrintModel**: Represents a 3D model with metadata
- **PrintJob**: Tracks print job history and status
- **Printer**: Stores printer connection information

### Key Components
- **STLFileManager**: Handles file operations (import, export, storage)
- **ModelConverter**: Converts between 3D formats (USDZ, OBJ, STL)
- **AnycubicPrinterAPI**: Communicates with printer web interface
- **ObjectScannerView**: LiDAR scanning interface (iOS only)

## Requirements

### iOS/iPadOS
- iOS 18.0+ (for Object Capture Kit)
- LiDAR sensor (iPhone 12 Pro and later, iPad Pro 2020 and later)
- Network access to communicate with printers

### macOS
- macOS 15.0+
- Can import and manage files, but cannot scan objects

### Frameworks Used
- SwiftUI: User interface
- SwiftData: Data persistence
- RealityKit: 3D rendering
- ModelIO: 3D model handling
- SceneKit: Thumbnail generation
- ObjectCaptureKit: LiDAR scanning (iOS only)

## Setup Instructions

### 1. Permissions
Add these to your Info.plist:
```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is required to scan 3D objects</string>

<key>NSLocalNetworkUsageDescription</key>
<string>Network access is required to communicate with your 3D printer</string>

<key>NSBonjourServices</key>
<array>
    <string>_http._tcp</string>
</array>
```

### 2. Capabilities
Enable these in your Xcode project:
- File Access (for importing STL files)
- Local Network (for printer communication)

### 3. Printer Configuration
1. Open the app and tap the printer icon
2. Tap "+" to add a printer
3. Enter printer name and IP address
4. Optionally enter API key (if your printer requires authentication)
5. Test connection to verify

## Usage Guide

### Scanning an Object
1. Tap "+" button and select "Scan Object"
2. Point camera at object and wait for detection
3. Move around the object to capture from all angles
4. Tap "Finish" when complete
5. App will process and convert to STL format

### Importing Files
1. Tap "+" button and select "Import File"
2. Choose STL, OBJ, or USDZ file from Files
3. File is copied to app and converted to STL if needed

### Printing a Model
1. Select a model from the library
2. Tap "Send to Printer"
3. Select printer from list
4. Choose whether to start printing immediately
5. Tap "Send" to upload

## Known Limitations

### Object Capture
- Requires iOS device with LiDAR
- Works best with matte, textured objects
- Reflective or transparent objects may not scan well
- Processing can take several minutes

### STL Conversion
- USDZ to STL conversion uses ModelIO
- Some complex geometry may require manual adjustment
- File size can be large for detailed scans

### Printer API
- Currently configured for Anycubic web interface
- May need adjustments for specific printer models
- Network connectivity required
- Some printers may use different API endpoints

## Customization

### Supporting Other Printers
The `AnycubicPrinterAPI` can be adapted for other printers by:
1. Updating API endpoints in the URL strings
2. Modifying authentication method if needed
3. Adjusting status response parsing

### File Format Support
To add support for other formats:
1. Extend `ModelConverter` with new conversion methods
2. Add file type to `fileImporter` allowed content types
3. Update import handling in `ContentView`

## Future Enhancements

- [ ] Live printer monitoring with temperature graphs
- [ ] Slice preview before printing
- [ ] Cloud storage integration
- [ ] Share models with other users
- [ ] Print time estimation
- [ ] Filament usage tracking
- [ ] Multi-printer job queue
- [ ] AR preview of scanned objects
- [ ] Advanced mesh editing tools

## Troubleshooting

### Scanning Issues
- Ensure adequate lighting
- Move slowly around object
- Keep object in frame
- Avoid shiny or transparent objects

### Connection Issues
- Verify printer is on same network
- Check IP address is correct
- Ensure printer web interface is enabled
- Try accessing printer web interface in Safari

### File Import Issues
- Verify file is valid STL/OBJ/USDZ
- Check file size isn't too large
- Ensure file isn't corrupted
- Try converting file externally first

## API Reference

### Anycubic Web Interface
The app communicates with Anycubic printers using HTTP endpoints:
- `GET /api/version` - Check printer availability
- `GET /api/printer` - Get printer status
- `GET /api/files` - List files on printer
- `POST /api/files/local` - Upload file
- `POST /api/files/local/{filename}` - Start print job

These endpoints follow a similar pattern to OctoPrint API, which many 3D printers support.

## Credits

Built with SwiftUI and SwiftData
Uses Apple's Object Capture framework for 3D scanning
ModelIO for 3D model handling
