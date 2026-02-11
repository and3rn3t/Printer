# Anycubic Photon Series — Network Protocol Research

> Research compiled from official SDCP protocol spec, photoNetLib (Java), photoNet (Android), hass_chitubox_printer (Home Assistant), and turbo-resin (open firmware).

---

## 1. Network Protocols — Three Distinct Generations

Anycubic Photon resin printers use **ChiTu mainboards** (made by Shenzhen CBD Technology). There are **three protocol generations**, and which one your printer uses depends on its age/model:

### Protocol A: "CBD Protocol" (Older ChiTu boards)

- **Transport:** UDP datagrams
- **Port:** 3000
- **Commands:** G-code/M-code style ASCII strings (`M20`, `M4000`, `M99999`, etc.)
- **Response format:** ASCII, prefixed with `ok` on success or `Error:` on failure
- **Character encoding:** ASCII (US-ASCII)
- **Used by:** Older MSLA printers with ChiTu boards (Elegoo Mars series, some Anycubic Mono models)

### Protocol B: "ACT Protocol" (Anycubic-specific)

- **Transport:** TCP socket
- **Port:** 6000
- **Commands:** Comma-delimited ASCII strings (`sysinfo,`, `getstatus,`, `goprint,filename,`, etc.)
- **Response format:** Comma-delimited ASCII, terminated with `end`
- **Character encoding:** GBK (Chinese encoding, important for Swift `String` handling)
- **Used by:** Anycubic Photon Mono SE, Photon Mono X, Photon X

### Protocol C: "SDCP V3.0.0" (Current generation — 2023+)

- **Transport:** WebSocket + HTTP
- **WebSocket port:** 3030 (path: `/websocket`)
- **HTTP port:** 3030 (for file uploads)
- **Commands:** JSON messages with MQTT-style topics
- **Video stream:** RTSP on port 554
- **Used by:** Anycubic Photon Mono M5s, Photon Mono M7, Elegoo Saturn 4 series, and other recent ChiTu-based printers

> **Key takeaway for your project:** You need to determine which protocol your specific Photon model uses. Newer models (M5s and later) use SDCP V3. Older Mono SE/X models use the ACT protocol.

---

## 2. Ports Summary

| Protocol | Discovery Port | Command Port | File Transfer Port | Video Port |
|----------|---------------|-------------|-------------------|------------|
| CBD      | 3000 (UDP)    | 3000 (UDP)  | 3000 (UDP, binary) | N/A        |
| ACT      | 48899 (UDP)   | 6000 (TCP)  | 6000 (TCP, binary) | N/A        |
| SDCP V3  | 3000 (UDP)    | 3030 (WebSocket) | 3030 (HTTP POST) | 554 (RTSP) |

---

## 3. Discovery Mechanism

### CBD Discovery (UDP broadcast on port 3000)

1. Client broadcasts `M99999` as a UDP packet to port 3000 on all broadcast addresses
2. Printer responds with device info in the format:

   ```
   ok MAC:00:e0:4c:XX:XX:XX IP:192.168.1.X VER:V1.4.1 ID:00,00,00,00,00,00,00,01 NAME:PrinterName
   ```

3. Response is parsed with regex: `MAC:(?<mac>...) IP:(?<ip>...) VER:(?<ver>...) ID:(?<id>...) NAME:(?<name>...)`

### ACT Discovery (UDP broadcast on port 48899)

1. Client broadcasts the string `www.usr.cn` as UDP to port 48899 on all broadcast addresses
2. Printer responds with: `192.168.1.X, 020000000000, USR-C322, 01.01.10`
3. Response is comma-separated: IP address, MAC, module type, firmware version

### SDCP V3 Discovery (UDP broadcast on port 3000)

1. Client broadcasts `M99999` as UDP to port 3000 (same as CBD)
2. Printer responds with **JSON**:

   ```json
   {
     "Id": "xxx",
     "Data": {
       "Name": "PrinterName",
       "MachineName": "MachineModel",
       "BrandName": "CBD",
       "MainboardIP": "192.168.1.2",
       "MainboardID": "000000000001d354",
       "ProtocolVersion": "V3.0.0",
       "FirmwareVersion": "V1.0.0"
     }
   }
   ```

3. If you get JSON back from the `M99999` broadcast, it's SDCP V3. If you get `ok MAC:...`, it's CBD. If nothing on 3000, try ACT discovery on 48899.

#### Swift Discovery Implementation Pattern

```swift
// Broadcast on all network interfaces
let interfaces = NetworkInterface.allInterfaces()
for iface in interfaces where iface.broadcastAddress != nil {
    // Send "M99999" via UDP to port 3000 (CBD/SDCP)
    // Send "www.usr.cn" via UDP to port 48899 (ACT)
    // Parse responses to determine protocol type
}
```

---

## 4. Command/Response Format

### CBD Protocol — M-code Commands (UDP)

| Command | M-Code | Description |
|---------|--------|-------------|
| System Info | `M99999` | Returns MAC, IP, version, ID, name |
| Get Status | `M4000` | Returns printer status with temperatures, Z position, print progress |
| Get Selected File | `M4006` | Returns currently selected file name |
| List Files | `M20` | Lists files on storage device |
| Select File | `M6032 '<filename>'` | Selects a file |
| Start Print | `M6030 '<filename>'` | Starts printing selected file |
| Pause Print | `M25` | Pauses current print |
| Resume Print | `M24` | Resumes paused print |
| Stop Print | `M33 I5` | Stops current print |
| Delete File | `M30 '<filename>'` | Deletes a file |
| Upload File | `M28 '<filename>'` | Begins file upload |
| Upload Stop | `M29` | Ends file upload |
| Read File | `M3001 I<offset>` | Reads file data at offset |
| Close File | `M22` | Closes currently open file |
| Set Name | `U100 '<newname>'` | Changes printer name |
| Z Home | `G28 Z0` | Homes Z axis |
| Z Move | `G0 Z<pos> F<speed>` | Moves Z axis |
| Z Stop | `M112` | Emergency stop Z movement |
| Z Absolute | `G90` | Sets absolute positioning mode |
| Z Relative | `G91` | Sets relative positioning mode |

**CBD Status Response Format:**

```
ok B:184/0 E1:185/0 E2:192/0 X:0.000 Y:0.000 Z:103.100 F:255/256 D:2062/51744/0 T:6844
```

Parsed with regex:

```
B:\d+/\d+ E1:\d+/\d+ E2:\d+/\d+ X:-?\d+.\d+ Y:-?\d+.\d+ Z:(?<z>-?\d+.\d+) F:\d+/\d+ D:(?<current>\d+)/(?<total>\d+)/(?<paused>\d+) T:(?<time>\d+)
```

- `B`: Board temp (current/target)
- `E1`/`E2`: Extruder temps
- `Z`: Current Z position (mm)
- `D`: Current layer / Total layers / Paused (0=no, 1=yes)
- `T`: Elapsed time (seconds)

**CBD Response Protocol:**

- Success: starts with `ok` followed by optional data
- Error: starts with `Error:` followed by error message
- Multi-packet: first bytes `0x6F 0x6B` ("ok"), may span multiple UDP packets

### ACT Protocol — Comma-delimited commands (TCP)

| Command | String | Description |
|---------|--------|-------------|
| System Info | `sysinfo,` | Returns model, version, ID, SSID |
| Get Status | `getstatus,` | Returns detailed print status |
| Get Mode | `getmode,` | Returns current mode |
| Get Firmware | `getFirmware,` | Returns firmware version |
| Get Name | `getname,` | Returns printer name |
| Set Name | `setname,<name>,` | Changes printer name |
| List Files | `getfile,` | Lists available files |
| Start Print | `goprint,<filename>,` | Starts printing a file |
| Delete File | `delfile,<filename>,` | Deletes a file |
| Stop Print | `stop,` | Stops current print |
| Pause Print | `pause,` | Pauses current print |
| Resume Print | `resume,` | Resumes paused print |
| Get Preview | `getPreview2,<filename>,` | Gets file preview image |
| Z Home | `setZhome,` | Homes Z axis |
| Z Move | `setZmove,<distance>,` | Moves Z axis |
| Z Stop | `setZstop,` | Stops Z movement |
| UV On | `setUVon,` | Turns on UV LED |
| UV Off | `setUVoff,` | Turns off UV LED |
| Detect | `detect,<i>,<j>,` | Runs detection routine |

**ACT Status Response:**

```
getstatus,print,Model2.pwmb,2338,88,2062,51744,6844,~178mL,UV,39.38,0.05,0,end
```

Format: `getstatus,<state>,<filename>,<?,<?,<current_layer>,<total_layers>,<time_seconds>,<resin_used>,<mode>,<temp>,<z_pos>,<?,end`

States: `stop`, `print`, `pause`, `finish`

**ACT Sysinfo Response:**

```
sysinfo,Photon Mono X,v0.1,0000000000000001,SomeSSID,end
```

Format: `sysinfo,<model>,<version>,<id>,<ssid>,end`

### SDCP V3.0.0 — JSON over WebSocket

**Connection:** `ws://<PrinterIP>:3030/websocket`

**Heartbeat:** Send `"ping"`, receive `"pong"`

**Message Topics (MQTT-style routing inside WebSocket):**

```
sdcp/request/${MainboardID}    — Client → Printer (commands)
sdcp/response/${MainboardID}   — Printer → Client (responses)
sdcp/status/${MainboardID}     — Printer → Client (status updates)
sdcp/attributes/${MainboardID} — Printer → Client (device attributes)
sdcp/error/${MainboardID}      — Printer → Client (errors)
sdcp/notice/${MainboardID}     — Printer → Client (notifications)
```

**Command Format (all commands follow this structure):**

```json
{
  "Id": "<brand-uuid>",
  "Data": {
    "Cmd": <command_number>,
    "Data": { /* command-specific parameters */ },
    "RequestID": "<unique-request-id>",
    "MainboardID": "<mainboard-id>",
    "TimeStamp": 1687069655,
    "From": 0
  },
  "Topic": "sdcp/request/${MainboardID}"
}
```

**From field values:**

| Value | Source |
|-------|--------|
| 0 | Local PC Software (LAN) |
| 1 | PC Software via Web |
| 2 | Web Client |
| 3 | Mobile App |
| 4 | Server |

**Response Format:**

```json
{
  "Id": "<brand-uuid>",
  "Data": {
    "Cmd": <command_number>,
    "Data": {
      "Ack": 0
    },
    "RequestID": "<matching-request-id>",
    "MainboardID": "<mainboard-id>",
    "TimeStamp": 1687069655
  },
  "Topic": "sdcp/response/${MainboardID}"
}
```

- `Ack: 0` = success, other values are error codes

---

## 5. Available Commands (SDCP V3)

| Cmd | Name | Parameters |
|-----|------|-----------|
| 0 | Status Refresh | `{}` — triggers fresh status report |
| 1 | Request Attributes | `{}` — triggers attribute report |
| 128 | Start Print | `{"Filename": "test.ctb", "StartLayer": 0}` |
| 129 | Pause Print | `{}` |
| 130 | Stop Print | `{}` |
| 131 | Resume Print | `{}` |
| 132 | Stop Feeding Material | `{}` |
| 133 | Skip Preheating | `{}` |
| 192 | Change Printer Name | `{"Name": "newName"}` |
| 255 | Terminate File Transfer | `{"Uuid": "...", "FileName": "..."}` |
| 258 | List Files | `{"Url": "/usb/yourPath"}` — `/usb/` for USB, `/local/` for onboard |
| 259 | Batch Delete Files | `{"FileList": ["/path/file1", "/path/file2"]}` |
| 320 | Get Historical Tasks | `{}` — returns task ID list |
| 321 | Get Task Details | `{"Id": ["taskId1", "taskId2"]}` |
| 386 | Enable/Disable Video Stream | `{"Enable": 0}` — 0=off, 1=on; response includes `VideoUrl` (RTSP) |
| 387 | Enable/Disable Time-lapse | `{"Enable": 0}` — 0=off, 1=on |

**File Upload (HTTP POST):**

```
POST http://<PrinterIP>:3030/uploadFile/upload
Content-Type: multipart/form-data

Headers/Fields:
  S-File-MD5: <md5hash>
  Check: '1'           // enable verification
  Offset: 0            // byte offset for chunked upload
  Uuid: <session-uuid> // same UUID for all chunks of one file
  TotalSize: 12345     // total file size in bytes
  File: (binary data)  // max 1MB per chunk
```

**Status Information (pushed by printer):**

- Print progress (current layer, total layers, percentage)
- Z position
- UV LED temperature
- Enclosure temperature
- Print time elapsed/remaining
- Current filename
- Machine status (idle, printing, paused, etc.)

**Attribute Information (pushed by printer):**

- Printer name, model, brand
- Firmware version
- IP address, MAC address
- XYZ build size
- Network status (WiFi vs Ethernet)
- USB disk connected
- Capabilities: `FILE_TRANSFER`, `PRINT_CONTROL`, `VIDEO_STREAM`
- Supported file types (e.g., `CTB`)
- Device self-check status (LCD connected, UV LED connected, Z-motor, strain gauge, etc.)

---

## 6. Authentication Requirements

- **CBD Protocol:** None. No authentication whatsoever.
- **ACT Protocol:** None. No authentication.
- **SDCP V3:** None for LAN communication. The protocol uses `Id` (brand UUID) and `MainboardID` for routing, but these are not secrets — they're broadcast during discovery. There is no login, password, token, or TLS.

> **Security note:** All three protocols are completely unauthenticated and unencrypted. Anyone on the same LAN can control the printer. This is expected for consumer devices but something to be aware of.

---

## 7. Differences Between Photon Generations

| Printer Model | Protocol | Discovery | Command Port | Notes |
|--------------|----------|-----------|--------------|-------|
| Photon (original) | ACT | UDP 48899 | TCP 6000 | GBK encoding |
| Photon S | ACT | UDP 48899 | TCP 6000 | GBK encoding |
| Photon Mono | ACT or CBD | Varies | Varies | Depends on board revision |
| Photon Mono SE | ACT | UDP 48899 | TCP 6000 | Confirmed working with photoNet |
| Photon Mono X | ACT | UDP 48899 | TCP 6000 | Confirmed working with photoNet |
| Photon Mono X 6Ks | Unknown | — | — | May use SDCP; needs testing |
| Photon Mono M3 | Neither ACT nor old CBD | — | — | photoNet README explicitly says "M3 will not work" |
| Photon Mono M5s | SDCP V3 | UDP 3000 | WS 3030 | JSON/WebSocket, modern protocol |
| Photon Mono M7 | SDCP V3 | UDP 3000 | WS 3030 | Latest generation |

> **Important:** The Photon M3 appears to be a transitional model that may use a different/intermediate protocol. Models from M5s onward use SDCP V3.

---

## 8. OctoPrint Compatibility

**No.** There is no OctoPrint-compatible interface on any Photon resin printer.

OctoPrint is designed for FDM printers using serial/USB G-code communication. Resin (MSLA/DLP) printers are fundamentally different:

- They don't use standard G-code streams
- They process pre-sliced binary files (`.photon`, `.ctb`, `.pwmb`, etc.)
- Print control is at the file level, not line-by-line G-code

The Anycubic FDM printers (i3 Mega, Kobra series) do support Marlin firmware with G-code and can work with OctoPrint, but the Photon resin series uses a completely proprietary protocol.

---

## 9. Existing Libraries and Implementations

### Java (most complete)

- **[SG-O/photoNetLib](https://github.com/SG-O/photoNetLib)** — Apache 2.0 licensed Java library supporting both CBD and ACT protocols. This is the most complete reverse-engineered implementation. Includes emulators for testing.
- **[SG-O/photoNet](https://github.com/SG-O/photoNet)** — Android app built on photoNetLib. Source of truth for real-world usage patterns.

### Python

- **[bushvin/sdcpapi](https://github.com/bushvin/sdcpapi)** (PyPI: `sdcpapi`) — Python library implementing SDCP V3 via WebSocket. Used by the Home Assistant integration.
- **[bushvin/hass_chitubox_printer](https://github.com/bushvin/hass_chitubox_printer)** — Home Assistant integration using sdcpapi. Tested on Elegoo Saturn 4 Ultra.

### Rust

- **[nviennot/turbo-resin](https://github.com/nviennot/turbo-resin)** — Open-source replacement firmware for ChiTu boards. Useful for understanding the hardware side.

### Swift

- **No existing Swift implementation exists.** Your project would be the first.

### JavaScript/TypeScript

- No known implementations.

---

## 10. ChiTu Board Communication Details

ChiTu boards (by Shenzhen CBD Technology / 创必得) are the de facto standard mainboards for consumer MSLA resin printers. They're used by Anycubic, Elegoo, Creality, Phrozen, and others.

### Board Features Relevant to Network Communication

- **WiFi module:** Typically a USR-C322 or similar (for ACT protocol printers)
- **Ethernet:** Some models have Ethernet (RJ45) in addition to WiFi
- **Storage:** USB drive and/or onboard flash
- **Camera:** Newer boards (SDCP V3) support camera modules with RTSP streaming on port 554

### SDCP V3 Capabilities Reported by Board

```json
"Capabilities": [
    "FILE_TRANSFER",   // Can receive files over network
    "PRINT_CONTROL",   // Can start/stop/pause prints
    "VIDEO_STREAM"     // Has camera, supports RTSP
]
```

### Device Status Structure (SDCP V3)

```json
"DevicesStatus": {
    "UVLEDConnected": true,
    "UVLEDTempSensorConnected": true,
    "LCDConnected": true,
    "ZMotorConnected": true,
    "RotaryMotorConnected": false,
    "StrainGaugeConnected": true,
    "CameraConnected": true
}
```

---

## Practical Recommendations for Swift Implementation

### Phase 1: Discovery

1. Use `NWConnection` (Network.framework) to send UDP broadcasts
2. Send `M99999` to port 3000 on all broadcast addresses
3. Also send `www.usr.cn` to port 48899 for ACT printers
4. Parse responses to auto-detect protocol type (JSON = SDCP V3, `ok MAC:` = CBD, comma-separated = ACT)

### Phase 2: Connection

- **SDCP V3:** Use `URLSessionWebSocketTask` to connect to `ws://<ip>:3030/websocket`
- **ACT:** Use `NWConnection` with TCP to port 6000
- **CBD:** Use `NWConnection` with UDP to port 3000

### Phase 3: Status Monitoring

- **SDCP V3:** Subscribe to WebSocket — printer pushes status automatically
- **ACT/CBD:** Poll periodically (e.g., every 2 seconds)

### Phase 4: Print Control

- All three protocols support: start, pause, resume, stop
- SDCP V3 adds: skip preheating, timelapse control, camera stream

### Phase 5: File Management

- List, delete, download files from printer storage
- Upload files (SDCP V3 uses HTTP multipart; CBD uses binary UDP; ACT uses TCP binary)

### Key Swift Framework Choices

- **Network.framework** (`NWConnection`, `NWListener`) for UDP/TCP
- **URLSession** for WebSocket (SDCP V3) and HTTP file upload
- **Foundation** JSON encoding/decoding for SDCP V3 messages
- **AVFoundation** or third-party for RTSP camera stream

---

## Source URLs

- SDCP V3 Protocol Spec: <https://github.com/cbd-tech/SDCP-Smart-Device-Control-Protocol-V3.0.0>
- photoNetLib (Java): <https://github.com/SG-O/photoNetLib>
- photoNet Android App: <https://github.com/SG-O/photoNet>
- Home Assistant Integration: <https://github.com/bushvin/hass_chitubox_printer>
- Python SDCP API: <https://github.com/bushvin/sdcpapi> (PyPI: sdcpapi)
- Open-source firmware: <https://github.com/nviennot/turbo-resin>
