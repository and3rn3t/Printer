# Required Info.plist Entries

Add these entries to your Info.plist file:

## Camera Access (for 3D Scanning)
```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is required to scan 3D objects using LiDAR</string>
```

## Local Network Access (for Printer Communication)
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Network access is required to communicate with your 3D printer on the local network</string>

<key>NSBonjourServices</key>
<array>
    <string>_http._tcp</string>
    <string>_printer._tcp</string>
</array>
```

## File Type Support
```xml
<key>UTImportedTypeDeclarations</key>
<array>
    <dict>
        <key>UTTypeConformsTo</key>
        <array>
            <string>public.data</string>
            <string>public.3d-content</string>
        </array>
        <key>UTTypeDescription</key>
        <string>STL 3D Model</string>
        <key>UTTypeIdentifier</key>
        <string>com.app.stl</string>
        <key>UTTypeTagSpecification</key>
        <dict>
            <key>public.filename-extension</key>
            <array>
                <string>stl</string>
            </array>
            <key>public.mime-type</key>
            <array>
                <string>model/stl</string>
                <string>application/sla</string>
            </array>
        </dict>
    </dict>
</array>
```

## Document Types (for File Import)
```xml
<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeName</key>
        <string>STL File</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>com.app.stl</string>
        </array>
        <key>LSHandlerRank</key>
        <string>Owner</string>
    </dict>
</array>
```

## Required Device Capabilities (Optional - if you want to require LiDAR)
```xml
<key>UIRequiredDeviceCapabilities</key>
<array>
    <string>lidar-sensor</string>
</array>
```

Note: Only add the UIRequiredDeviceCapabilities if you want to restrict the app to LiDAR-capable devices. Otherwise, the app will work on all devices but scanning will only be available on LiDAR devices.

## Background Modes (Optional - for background uploads)
If you want to allow file uploads to continue in the background:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>network-authentication</string>
</array>
```
