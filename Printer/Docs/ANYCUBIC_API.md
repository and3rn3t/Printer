# Anycubic Photon ACT Protocol Reference

> Reverse-engineered from a **Photon Mono X 6K** (firmware V0.2.2) on 2025-02-11.

## Overview

Anycubic Photon resin printers communicate via a proprietary **ACT protocol** over TCP port **6000**. This is **not** OctoPrint-compatible — FDM printers may use HTTP, but Photon-series printers use this simpler text-based TCP protocol.

## Connection

| Property | Value |
|----------|-------|
| Transport | TCP |
| Port | 6000 |
| Encoding | UTF-8 |
| Line ending | `\r\n` (send) |

Each command opens a fresh TCP connection (short-lived), though persistent connections also work.

## Command Format

**Request:** `command[,param1,param2,...]\r\n`

**Response:** `command,value1,value2,...,end`

- The first field in the response echoes the command name
- The last field is always the literal string `end`
- Values between the echo and `end` are the response payload
- Error responses use `ERROR<N>` values (e.g., `ERROR1`, `ERROR2`)

## Confirmed Commands

### `getstatus`

Get the current printer state.

```
→ getstatus
← getstatus,stop,end
```

| Response Value | Meaning |
|---------------|---------|
| `stop` | Idle / not printing |
| `print` | Currently printing |
| `pause` | Print is paused |

### `getmode`

Get the current operating mode.

```
→ getmode
← getmode,0,end
```

| Mode | Meaning |
|------|---------|
| `0` | Idle / normal |

### `sysinfo`

Get system information — model name, firmware version, serial number, WiFi SSID.

```
→ sysinfo
← sysinfo,Photon Mono X 6K,V0.2.2,00001A9F00030034,andernet,end
```

| Field | Example | Description |
|-------|---------|-------------|
| 1 | `Photon Mono X 6K` | Model name |
| 2 | `V0.2.2` | Firmware version |
| 3 | `00001A9F00030034` | Serial number |
| 4 | `andernet` | Connected WiFi SSID |

### `getwifi`

Get the connected WiFi network name.

```
→ getwifi
← getwifi,andernet,end
```

### `getname`

Get the printer's display name. Response may contain garbled/non-UTF8 characters.

```
→ getname
← getname,<name>,end
```

### `gopause`

Pause the current print job.

```
→ gopause
← gopause,ok,end      (success)
← gopause,ERROR1,end  (not printing)
```

### `goresume`

Resume a paused print job.

```
→ goresume
← goresume,ok,end      (success)
← goresume,ERROR1,end  (not paused)
```

### `gostop`

Stop/cancel the current print job.

```
→ gostop
← gostop,ok,end      (success)
← gostop,ERROR1,end  (not printing)
```

### `goprint,<filename>`

Start printing a file stored on the printer's USB/internal storage.

```
→ goprint,model.pwmx
← goprint,ok,end       (success)
← goprint,ERROR2,end   (file not found)
```

## Error Codes

| Code | Meaning |
|------|---------|
| `ERROR1` | Operation not applicable (e.g., pause when not printing) |
| `ERROR2` | File not found or invalid parameter |

## Discovery

| Method | Result |
|--------|--------|
| **TCP probe port 6000** | ✅ Works — connect then send `sysinfo` |
| UDP broadcast port 3000 | ❌ No response on this model |
| UDP broadcast port 48899 | ❌ No response on this model |
| HTTP port 18910 | ❌ HTTP endpoint not available on Photon resin printers |

## Commands Tested but Not Responding

These commands were probed but returned `ERROR1` or no response:

- `getpara` — printer parameters (may need arguments)
- `getfiles` / `getfile` — file listing (may need path argument)
- `gettemp` — temperature info (resin printers don't report this)
- `gethome` — home axes (not applicable for resin)
- `getlight` — UV light status (may need specific state)

## File Format Notes

Photon printers use sliced file formats (`.pwmx`, `.pwma`, etc.) — they **cannot** print raw STL/OBJ files. The app will need to either:

1. Slice models externally (Anycubic Photon Workshop, Lychee Slicer)
2. Transfer pre-sliced files to the printer's USB storage
3. Implement slicing (future — very complex)

## Implementation

- **`PhotonPrinterService.swift`** — Actor-based ACT protocol client
- **`AnycubicPrinterAPI.swift`** — Unified API that delegates to PhotonPrinterService for ACT printers
- **`PrinterDiscovery.swift`** — Subnet scanner probes port 6000 for ACT printers

## Test Printer

| Property | Value |
|----------|-------|
| Model | Photon Mono X 6K |
| Firmware | V0.2.2 |
| Serial | 00001A9F00030034 |
| IP Address | 192.168.1.49 |
| Port | 6000 |
| WiFi | andernet |
