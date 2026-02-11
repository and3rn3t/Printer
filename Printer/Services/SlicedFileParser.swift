//
//  SlicedFileParser.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import CoreGraphics

// MARK: - Sliced File Metadata

/// Metadata extracted from sliced 3D printing files (PWMX, PWMA, CTB, GCode)
struct SlicedFileMetadata: Sendable {
    /// Total number of layers in the print
    let layerCount: UInt32
    /// Layer height in millimeters
    let layerHeight: Float
    /// Normal layer exposure time in seconds
    let exposureTime: Float
    /// Bottom layer exposure time in seconds
    let bottomExposureTime: Float
    /// Number of bottom layers
    let bottomLayerCount: UInt32
    /// Estimated print time in seconds
    let printTime: UInt32
    /// Estimated resin/material volume in milliliters
    let volumeMl: Float
    /// Printer X resolution in pixels
    let resolutionX: UInt32
    /// Printer Y resolution in pixels
    let resolutionY: UInt32
    /// Pixel size in micrometers (PWMX only)
    let pixelSizeUm: Float?
    /// Total print height in millimeters
    let printHeight: Float?
    /// Lift height in millimeters
    let liftHeight: Float?
    /// Lift speed in mm/s
    let liftSpeed: Float?
}

// MARK: - Parser Errors

/// Errors that can occur during sliced file parsing
enum SlicedFileParserError: LocalizedError {
    case fileNotFound
    case fileTooSmall
    case invalidMagic(String)
    case invalidHeader
    case unsupportedFormat(String)
    case readError

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Sliced file not found"
        case .fileTooSmall:
            return "File is too small to contain valid header data"
        case .invalidMagic(let expected):
            return "Invalid file magic bytes (expected \(expected))"
        case .invalidHeader:
            return "Could not parse file header"
        case .unsupportedFormat(let ext):
            return "Unsupported sliced file format: \(ext)"
        case .readError:
            return "Error reading file data"
        }
    }
}

// MARK: - Sliced File Parser

/// Parses binary headers from sliced 3D printing files to extract metadata
///
/// Supports:
/// - **PWMX/PWMA/PWMB** — Anycubic Photon Workshop format (section-based binary)
/// - **CTB** — ChiTuBox format (fixed header binary)
/// - **GCode** — FDM slicer output (text-based comment parsing)
actor SlicedFileParser {

    // MARK: - Public API

    /// Parse metadata from a sliced file at the given URL
    /// - Parameter url: URL to the sliced file
    /// - Returns: Extracted metadata, or nil if parsing fails
    func parseMetadata(from url: URL) async -> SlicedFileMetadata? {
        let ext = url.pathExtension.lowercased()
        do {
            switch ext {
            case "pwmx", "pwma", "pwmb", "pwmo", "pwms", "pws", "pw0",
                 "dlp", "dl2p", "pmx2", "px6s", "pm3n", "pm4n",
                 "pmsq", "pm3", "pm3m", "pm3r", "pm5", "pm5s", "m5sp", "pwc":
                return try parsePWMX(from: url)
            case "ctb", "cbddlp", "photon", "phz":
                return try parseCTB(from: url)
            case "gcode", "gco":
                return try parseGCode(from: url)
            default:
                return nil
            }
        } catch {
            print("SlicedFileParser: Failed to parse \(ext) file: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - PWMX / Anycubic Photon Workshop Format

    /// Binary layout constants for Anycubic Photon Workshop files
    private enum PWMXConstants {
        static let markSize = 12
        static let fileMarkString = "ANYCUBIC"
        static let headerMarkString = "HEADER"
        static let layerDefMarkString = "LAYERDEF"
        static let tableBaseLength = markSize + 4 // mark (12) + tableLength (4)
    }

    /// Parse an Anycubic Photon Workshop format file (.pwmx, .pwma, etc.)
    ///
    /// File structure:
    /// - FileMark: "ANYCUBIC" (12 bytes) | Version (uint32) | NumberOfTables (uint32) | HeaderAddress (uint32) | ...
    /// - At HeaderAddress: "HEADER" (12 bytes) | TableLength (uint32) | PixelSizeUm (float) | LayerHeight (float) | ...
    /// - At LayerDefinitionAddress: "LAYERDEF" (12 bytes) | TableLength (uint32) | LayerCount (uint32) | ...
    private func parsePWMX(from url: URL) throws -> SlicedFileMetadata {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SlicedFileParserError.fileNotFound
        }

        guard let fileHandle = FileHandle(forReadingAtPath: url.path) else {
            throw SlicedFileParserError.readError
        }
        defer { fileHandle.closeFile() }

        // Read FileMark section (minimum 44 bytes for v1)
        let fileMarkData = fileHandle.readData(ofLength: 80) // Extra space for v516+ addresses
        guard fileMarkData.count >= 44 else {
            throw SlicedFileParserError.fileTooSmall
        }

        // Validate magic: first 12 bytes should start with "ANYCUBIC"
        let markBytes = fileMarkData.prefix(PWMXConstants.markSize)
        let markString = String(data: markBytes.prefix(8), encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""
        guard markString == PWMXConstants.fileMarkString else {
            throw SlicedFileParserError.invalidMagic(PWMXConstants.fileMarkString)
        }

        // Parse FileMark offsets
        let version = fileMarkData.readUInt32(at: 12)
        let headerAddress = fileMarkData.readUInt32(at: 20)
        let layerDefinitionAddress = fileMarkData.readUInt32(at: 36)

        // Read Header section
        fileHandle.seek(toFileOffset: UInt64(headerAddress))
        let headerData = fileHandle.readData(ofLength: 120) // Table base (16) + header fields (~100 bytes)
        guard headerData.count >= 100 else {
            throw SlicedFileParserError.invalidHeader
        }

        // Validate header section mark
        let headerMark = String(data: headerData.prefix(6), encoding: .utf8) ?? ""
        guard headerMark == PWMXConstants.headerMarkString else {
            throw SlicedFileParserError.invalidHeader
        }

        // Header fields start after TableBaseLength (16 bytes)
        let hdr = PWMXConstants.tableBaseLength
        let pixelSizeUm = headerData.readFloat(at: hdr + 0)
        let layerHeight = headerData.readFloat(at: hdr + 4)
        let exposureTime = headerData.readFloat(at: hdr + 8)
        // WaitTimeBeforeCure at hdr + 12
        let bottomExposureTime = headerData.readFloat(at: hdr + 16)
        let bottomLayersCount = headerData.readFloat(at: hdr + 20)
        let liftHeight = headerData.readFloat(at: hdr + 24)
        let liftSpeed = headerData.readFloat(at: hdr + 28) // mm/s
        // RetractSpeed at hdr + 32
        let volumeMl = headerData.readFloat(at: hdr + 36)
        // AntiAliasing at hdr + 40
        let resolutionX = headerData.readUInt32(at: hdr + 44)
        let resolutionY = headerData.readUInt32(at: hdr + 48)
        // WeightG at hdr + 52, Price at hdr + 56, Currency at hdr + 60, PerLayerSettings at hdr + 64
        let printTime = headerData.readUInt32(at: hdr + 68)

        // Read LayerDefinition to get LayerCount
        var layerCount: UInt32 = 0
        if layerDefinitionAddress > 0 {
            fileHandle.seek(toFileOffset: UInt64(layerDefinitionAddress))
            let layerDefData = fileHandle.readData(ofLength: 24)
            if layerDefData.count >= 20 {
                // After table mark (12) + tableLength (4) = offset 16 → LayerCount (uint32)
                layerCount = layerDefData.readUInt32(at: PWMXConstants.tableBaseLength)
            }
        }

        // Calculate print height from layer count and height
        let printHeight = Float(layerCount) * layerHeight

        return SlicedFileMetadata(
            layerCount: layerCount,
            layerHeight: layerHeight,
            exposureTime: exposureTime,
            bottomExposureTime: bottomExposureTime,
            bottomLayerCount: UInt32(bottomLayersCount),
            printTime: printTime,
            volumeMl: volumeMl,
            resolutionX: resolutionX,
            resolutionY: resolutionY,
            pixelSizeUm: pixelSizeUm,
            printHeight: printHeight > 0 ? printHeight : nil,
            liftHeight: liftHeight > 0 ? liftHeight : nil,
            liftSpeed: liftSpeed > 0 ? liftSpeed : nil
        )
    }

    // MARK: - CTB / ChiTuBox Format

    /// Binary layout constants for ChiTuBox files
    private enum CTBConstants {
        static let magicCBDDLP: UInt32 = 0x12FD0019
        static let magicCTB: UInt32 = 0x12FD0086
        static let magicCTBv4: UInt32 = 0x12FD0106
        static let magicCTBv4GK: UInt32 = 0xFF220810
        static let magicPHZ: UInt32 = 0x9FDA83AE
        static let headerSize = 92 // Minimum header bytes needed
    }

    /// Parse a ChiTuBox format file (.ctb, .cbddlp, .photon, .phz)
    ///
    /// Header layout (all little-endian):
    /// - [0] Magic (uint32) — 0x12FD0086 for CTB
    /// - [4] Version (uint32)
    /// - [8-16] BedSize X/Y/Z (3× float)
    /// - [20-24] Unknown (2× uint32)
    /// - [28] TotalHeightMM (float)
    /// - [32] LayerHeightMM (float)
    /// - [36] ExposureSeconds (float)
    /// - [40] BottomExposureSeconds (float)
    /// - [48] BottomLayersCount (uint32)
    /// - [52] ResolutionX (uint32)
    /// - [56] ResolutionY (uint32)
    /// - [68] LayerCount (uint32)
    /// - [76] PrintTime (uint32, seconds)
    /// - [84] PrintParametersOffset (uint32)
    private func parseCTB(from url: URL) throws -> SlicedFileMetadata {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SlicedFileParserError.fileNotFound
        }

        guard let fileHandle = FileHandle(forReadingAtPath: url.path) else {
            throw SlicedFileParserError.readError
        }
        defer { fileHandle.closeFile() }

        // Read header (at least 92 bytes)
        let headerData = fileHandle.readData(ofLength: CTBConstants.headerSize)
        guard headerData.count >= CTBConstants.headerSize else {
            throw SlicedFileParserError.fileTooSmall
        }

        // Validate magic bytes
        let magic = headerData.readUInt32(at: 0)
        let isPHZ = magic == CTBConstants.magicPHZ
        guard magic == CTBConstants.magicCBDDLP ||
              magic == CTBConstants.magicCTB ||
              magic == CTBConstants.magicCTBv4 ||
              magic == CTBConstants.magicCTBv4GK ||
              isPHZ else {
            throw SlicedFileParserError.invalidMagic("CTB/CBDDLP/PHZ")
        }

        // Parse header fields
        let totalHeightMM = headerData.readFloat(at: 28)
        let layerHeightMM = headerData.readFloat(at: 32)
        let exposureSeconds = headerData.readFloat(at: 36)
        let bottomExposureSeconds = headerData.readFloat(at: 40)
        let bottomLayersCount = headerData.readUInt32(at: 48)
        let resolutionX = headerData.readUInt32(at: 52)
        let resolutionY = headerData.readUInt32(at: 56)
        let layerCount = headerData.readUInt32(at: 68)
        let printTime = headerData.readUInt32(at: 76)
        let printParametersOffset = headerData.readUInt32(at: 84)

        // Try reading PrintParameters for VolumeMl and lift settings
        var volumeMl: Float = 0
        var liftHeight: Float = 0
        var liftSpeed: Float = 0

        if printParametersOffset > 0 {
            fileHandle.seek(toFileOffset: UInt64(printParametersOffset))
            let printParamsData = fileHandle.readData(ofLength: 28)
            if printParamsData.count >= 24 {
                // PrintParameters layout:
                // [0] BottomLiftHeight (float)
                // [4] BottomLiftSpeed (float)
                // [8] LiftHeight (float)
                // [12] LiftSpeed (float)
                // [16] RetractSpeed (float)
                // [20] VolumeMl (float)
                liftHeight = printParamsData.readFloat(at: 8)
                liftSpeed = printParamsData.readFloat(at: 12)
                volumeMl = printParamsData.readFloat(at: 20)
            }
        }

        return SlicedFileMetadata(
            layerCount: layerCount,
            layerHeight: layerHeightMM,
            exposureTime: exposureSeconds,
            bottomExposureTime: bottomExposureSeconds,
            bottomLayerCount: bottomLayersCount,
            printTime: printTime,
            volumeMl: volumeMl,
            resolutionX: resolutionX,
            resolutionY: resolutionY,
            pixelSizeUm: nil,
            printHeight: totalHeightMM > 0 ? totalHeightMM : nil,
            liftHeight: liftHeight > 0 ? liftHeight : nil,
            liftSpeed: liftSpeed > 0 ? liftSpeed : nil
        )
    }

    // MARK: - GCode Format

    /// Parse a GCode file for metadata from slicer comments
    ///
    /// Common comment patterns:
    /// - `;Layer height: 0.05` / `; layer_height = 0.05`
    /// - `;TIME:12345` / `;PRINT.TIME:12345` / `;estimated printing time`
    /// - `;LAYER_COUNT:100` / `;total layers: 100`
    /// - `;Filament used: 1.23m` / `;filament_used_mm = 1230`
    private func parseGCode(from url: URL) throws -> SlicedFileMetadata {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SlicedFileParserError.fileNotFound
        }

        // Read only the first 8KB — slicer metadata is always in comments at the top or bottom
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { fileHandle.closeFile() }

        let headData = fileHandle.readData(ofLength: 8192)
        let headText = String(data: headData, encoding: .utf8) ?? ""

        // Also read the last 4KB for slicers that put metadata at the end
        let fileSize = fileHandle.seekToEndOfFile()
        var tailText = ""
        if fileSize > 8192 {
            let tailStart = max(8192, fileSize - 4096)
            fileHandle.seek(toFileOffset: tailStart)
            let tailData = fileHandle.readData(ofLength: Int(fileSize - tailStart))
            tailText = String(data: tailData, encoding: .utf8) ?? ""
        }

        let searchText = headText + "\n" + tailText

        var layerHeight: Float = 0
        var layerCount: UInt32 = 0
        var printTime: UInt32 = 0
        var filamentUsedMm: Float = 0

        for line in searchText.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(";") else { continue }
            let comment = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            let lower = comment.lowercased()

            // Layer height
            if layerHeight == 0 {
                if let value = extractFloat(from: comment, keys: ["layer_height", "layer height", "layerHeight"]) {
                    layerHeight = value
                }
            }

            // Layer count
            if layerCount == 0 {
                if let value = extractUInt(from: comment, keys: ["LAYER_COUNT", "total layers", "total_layers", "Layer count"]) {
                    layerCount = value
                }
            }

            // Print time
            if printTime == 0 {
                if lower.hasPrefix("time:") {
                    if let value = UInt32(comment.dropFirst(5).trimmingCharacters(in: .whitespaces)) {
                        printTime = value
                    }
                } else if let value = extractUInt(from: comment, keys: ["PRINT.TIME", "estimated_print_time", "print_time"]) {
                    printTime = value
                }
            }

            // Filament used (convert meters to mm)
            if filamentUsedMm == 0 {
                if lower.contains("filament used") || lower.contains("filament_used") {
                    if let value = extractFloat(from: comment, keys: ["filament used", "filament_used_mm", "Filament used"]) {
                        // Heuristic: if value < 100, it's likely in meters; convert to mm
                        filamentUsedMm = value < 100 ? value * 1000 : value
                    }
                }
            }
        }

        return SlicedFileMetadata(
            layerCount: layerCount,
            layerHeight: layerHeight,
            exposureTime: 0,
            bottomExposureTime: 0,
            bottomLayerCount: 0,
            printTime: printTime,
            volumeMl: 0, // GCode doesn't typically store volume
            resolutionX: 0,
            resolutionY: 0,
            pixelSizeUm: nil,
            printHeight: layerCount > 0 && layerHeight > 0 ? Float(layerCount) * layerHeight : nil,
            liftHeight: nil,
            liftSpeed: nil
        )
    }

    // MARK: - Helpers

    /// Extract a float value from a comment line matching any of the given keys
    private func extractFloat(from comment: String, keys: [String]) -> Float? {
        for key in keys {
            if let range = comment.range(of: key, options: .caseInsensitive) {
                let after = comment[range.upperBound...]
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "=", with: "")
                    .replacingOccurrences(of: ":", with: "")
                    .trimmingCharacters(in: .whitespaces)
                // Take first word (stop at space, "m", etc.)
                let numStr = after.prefix(while: { $0.isNumber || $0 == "." || $0 == "-" })
                if let value = Float(numStr) {
                    return value
                }
            }
        }
        return nil
    }

    /// Extract a UInt32 value from a comment line matching any of the given keys
    private func extractUInt(from comment: String, keys: [String]) -> UInt32? {
        for key in keys {
            if let range = comment.range(of: key, options: .caseInsensitive) {
                let after = comment[range.upperBound...]
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "=", with: "")
                    .replacingOccurrences(of: ":", with: "")
                    .trimmingCharacters(in: .whitespaces)
                let numStr = after.prefix(while: { $0.isNumber })
                if let value = UInt32(numStr) {
                    return value
                }
            }
        }
        return nil
    }

    // MARK: - Thumbnail Extraction

    /// Extract an embedded preview thumbnail from a sliced file
    /// - Parameter url: URL to the sliced file
    /// - Returns: PNG image data, or nil if no thumbnail is available
    func extractThumbnail(from url: URL) async -> Data? {
        let ext = url.pathExtension.lowercased()
        do {
            switch ext {
            case "pwmx", "pwma", "pwmb", "pwmo", "pwms", "pws", "pw0",
                 "dlp", "dl2p", "pmx2", "px6s", "pm3n", "pm4n",
                 "pmsq", "pm3", "pm3m", "pm3r", "pm5", "pm5s", "m5sp", "pwc":
                return try extractPWMXThumbnail(from: url)
            case "ctb", "cbddlp", "photon", "phz":
                return try extractCTBThumbnail(from: url)
            default:
                return nil
            }
        } catch {
            print("SlicedFileParser: Failed to extract thumbnail from \(ext): \(error.localizedDescription)")
            return nil
        }
    }

    /// Extract thumbnail from a PWMX/Anycubic Photon Workshop file
    ///
    /// Preview section layout at PreviewAddress (FileMark offset 24):
    /// - "PREVIEW" mark (12 bytes) + TableLength (uint32)
    /// - ResolutionX (uint32, default 224)
    /// - "x" mark (4 bytes)
    /// - ResolutionY (uint32, default 168)
    /// - Raw RGB565 pixel data (ResX × ResY × 2 bytes)
    private func extractPWMXThumbnail(from url: URL) throws -> Data? {
        guard let fileHandle = FileHandle(forReadingAtPath: url.path) else {
            throw SlicedFileParserError.readError
        }
        defer { fileHandle.closeFile() }

        // Read FileMark to get PreviewAddress
        let fileMarkData = fileHandle.readData(ofLength: 80)
        guard fileMarkData.count >= 28 else {
            throw SlicedFileParserError.fileTooSmall
        }

        // Validate magic
        let markString = String(data: fileMarkData.prefix(8), encoding: .utf8)?
            .trimmingCharacters(in: .controlCharacters) ?? ""
        guard markString == PWMXConstants.fileMarkString else {
            throw SlicedFileParserError.invalidMagic(PWMXConstants.fileMarkString)
        }

        // PreviewAddress is at FileMark offset 24
        let previewAddress = fileMarkData.readUInt32(at: 24)
        guard previewAddress > 0 else { return nil }

        // Seek to preview section
        fileHandle.seek(toFileOffset: UInt64(previewAddress))

        // Read preview header: mark (12) + tableLength (4) + resX (4) + "x" (4) + resY (4) = 28 bytes
        let previewHeader = fileHandle.readData(ofLength: 28)
        guard previewHeader.count >= 28 else { return nil }

        // Validate "PREVIEW" mark (first 7 bytes)
        let previewMark = String(data: previewHeader.prefix(7), encoding: .utf8) ?? ""
        guard previewMark == "PREVIEW" else { return nil }

        let resolutionX = previewHeader.readUInt32(at: PWMXConstants.tableBaseLength)      // offset 16
        let resolutionY = previewHeader.readUInt32(at: PWMXConstants.tableBaseLength + 8)   // offset 24 (after 4-byte "x" mark)

        guard resolutionX > 0, resolutionY > 0,
              resolutionX <= 1024, resolutionY <= 1024 else { return nil }

        // Read raw RGB565 pixel data
        let dataSize = Int(resolutionX * resolutionY) * 2
        let pixelData = fileHandle.readData(ofLength: dataSize)
        guard pixelData.count == dataSize else { return nil }

        return decodeRGB565(pixelData, width: Int(resolutionX), height: Int(resolutionY))
    }

    /// Extract thumbnail from a CTB/ChiTuBox format file
    ///
    /// Header offset 60: PreviewLargeOffsetAddress → Preview struct:
    /// - ResolutionX (uint32) + ResolutionY (uint32)
    /// - ImageOffset (uint32) + ImageLength (uint32)
    /// - 4 unknown uint32s
    /// Image data at ImageOffset is RLE-compressed RGB15
    private func extractCTBThumbnail(from url: URL) throws -> Data? {
        guard let fileHandle = FileHandle(forReadingAtPath: url.path) else {
            throw SlicedFileParserError.readError
        }
        defer { fileHandle.closeFile() }

        // Read header to get preview offset
        let headerData = fileHandle.readData(ofLength: CTBConstants.headerSize)
        guard headerData.count >= CTBConstants.headerSize else {
            throw SlicedFileParserError.fileTooSmall
        }

        // Validate magic
        let magic = headerData.readUInt32(at: 0)
        guard magic == CTBConstants.magicCBDDLP ||
              magic == CTBConstants.magicCTB ||
              magic == CTBConstants.magicCTBv4 ||
              magic == CTBConstants.magicCTBv4GK ||
              magic == CTBConstants.magicPHZ else {
            throw SlicedFileParserError.invalidMagic("CTB/CBDDLP/PHZ")
        }

        // PreviewLargeOffsetAddress at header offset 60 (large preview)
        // PreviewSmallOffsetAddress at header offset 72 (small preview)
        let previewOffset = headerData.readUInt32(at: 60)
        guard previewOffset > 0 else { return nil }

        // Seek to preview struct
        fileHandle.seek(toFileOffset: UInt64(previewOffset))

        // Preview struct: ResX (4) + ResY (4) + ImageOffset (4) + ImageLength (4) + 4 unknowns (16) = 32 bytes
        let previewStruct = fileHandle.readData(ofLength: 32)
        guard previewStruct.count >= 16 else { return nil }

        let resolutionX = previewStruct.readUInt32(at: 0)
        let resolutionY = previewStruct.readUInt32(at: 4)
        let imageOffset = previewStruct.readUInt32(at: 8)
        let imageLength = previewStruct.readUInt32(at: 12)

        guard resolutionX > 0, resolutionY > 0,
              resolutionX <= 1024, resolutionY <= 1024,
              imageOffset > 0, imageLength > 0 else { return nil }

        // Seek to image data
        fileHandle.seek(toFileOffset: UInt64(imageOffset))
        let rleData = fileHandle.readData(ofLength: Int(imageLength))
        guard rleData.count == Int(imageLength) else { return nil }

        return decodeChiTuRLE15(rleData, width: Int(resolutionX), height: Int(resolutionY))
    }

    // MARK: - Image Decoding

    /// Decode raw RGB565 pixel data to PNG
    ///
    /// RGB565 format: each pixel is 2 bytes (little-endian)
    /// - Bits [15:11] = Red (5 bits)
    /// - Bits [10:5] = Green (6 bits)
    /// - Bits [4:0] = Blue (5 bits)
    private func decodeRGB565(_ data: Data, width: Int, height: Int) -> Data? {
        let pixelCount = width * height
        var rgba = [UInt8](repeating: 255, count: pixelCount * 4)

        data.withUnsafeBytes { buffer in
            for i in 0..<pixelCount {
                let offset = i * 2
                guard offset + 1 < buffer.count else { break }
                let pixel = UInt16(buffer[offset]) | (UInt16(buffer[offset + 1]) << 8)

                let r = (pixel >> 11) & 0x1F
                let g = (pixel >> 5) & 0x3F
                let b = pixel & 0x1F

                rgba[i * 4 + 0] = UInt8(r * 255 / 31)
                rgba[i * 4 + 1] = UInt8(g * 255 / 63)
                rgba[i * 4 + 2] = UInt8(b * 255 / 31)
                rgba[i * 4 + 3] = 255
            }
        }

        return createPNGFromRGBA(rgba, width: width, height: height)
    }

    /// Decode ChiTu RLE15 compressed image data to PNG
    ///
    /// Each uint16 in the stream: `RRRRRGGGGGBBBBBX`
    /// - If X (bit 0) is 0: single pixel, color = pixel >> 1
    /// - If X (bit 0) is 1: next uint16 is the run length count
    private func decodeChiTuRLE15(_ data: Data, width: Int, height: Int) -> Data? {
        let pixelCount = width * height
        var rgba = [UInt8](repeating: 255, count: pixelCount * 4)
        var pixelIndex = 0

        data.withUnsafeBytes { buffer in
            var i = 0
            while i + 1 < buffer.count && pixelIndex < pixelCount {
                let value = UInt16(buffer[i]) | (UInt16(buffer[i + 1]) << 8)
                i += 2

                let isRLE = (value & 0x0001) != 0
                let color15 = value >> 1  // 15-bit color

                // Decode RGB555: RRRRRGGGGGBBBBB
                let r = (color15 >> 10) & 0x1F
                let g = (color15 >> 5) & 0x1F
                let b = color15 & 0x1F

                let r8 = UInt8(r * 255 / 31)
                let g8 = UInt8(g * 255 / 31)
                let b8 = UInt8(b * 255 / 31)

                var runLength = 1
                if isRLE && i + 1 < buffer.count {
                    runLength = Int(UInt16(buffer[i]) | (UInt16(buffer[i + 1]) << 8))
                    i += 2
                }

                for _ in 0..<runLength {
                    guard pixelIndex < pixelCount else { break }
                    rgba[pixelIndex * 4 + 0] = r8
                    rgba[pixelIndex * 4 + 1] = g8
                    rgba[pixelIndex * 4 + 2] = b8
                    rgba[pixelIndex * 4 + 3] = 255
                    pixelIndex += 1
                }
            }
        }

        return createPNGFromRGBA(rgba, width: width, height: height)
    }

    /// Convert raw RGBA pixel buffer to PNG data using CoreGraphics
    private func createPNGFromRGBA(_ rgba: [UInt8], width: Int, height: Int) -> Data? {
        let bitsPerComponent = 8
        let bitsPerPixel = 32
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: UnsafeMutableRawPointer(mutating: rgba),
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        guard let cgImage = context.makeImage() else { return nil }

        #if canImport(UIKit)
        let image = UIImage(cgImage: cgImage)
        return image.pngData()
        #elseif canImport(AppKit)
        let image = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        guard let tiffRep = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffRep) else { return nil }
        return bitmapRep.representation(using: .png, properties: [:])
        #else
        return nil
        #endif
    }
}

// MARK: - Data Extension for Binary Reading

private extension Data {
    /// Read a little-endian UInt32 at the given byte offset
    func readUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: offset, as: UInt32.self).littleEndian
        }
    }

    /// Read a little-endian Float32 at the given byte offset
    func readFloat(at offset: Int) -> Float {
        guard offset + 4 <= count else { return 0 }
        let bits = readUInt32(at: offset)
        return Float(bitPattern: bits)
    }
}
