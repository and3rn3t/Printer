//
//  PhotonPrinterService.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import Foundation
import Network

/// Communicates with Anycubic Photon resin printers via the ACT TCP protocol.
///
/// Photon printers (Mono X, Mono X 6K, etc.) expose a TCP server on port 6000
/// that accepts comma-delimited text commands and returns comma-delimited responses.
///
/// Protocol format:
/// - Send: `command[,param1,param2,...]\r\n`
/// - Receive: `command,result1,result2,...,end`
///
/// Discovery: UDP broadcast on port 3000 (some models) or TCP probe on port 6000.
actor PhotonPrinterService {

    /// Shared singleton instance — avoids creating redundant NWConnection instances
    static let shared = PhotonPrinterService()

    // MARK: - Types

    /// Errors specific to Photon printer communication
    enum PhotonError: LocalizedError {
        case connectionFailed(String)
        case commandFailed(command: String, error: String)
        case invalidResponse(String)
        case timeout
        case notPrinting
        case fileNotFound
        case disconnected

        var errorDescription: String? {
            switch self {
            case .connectionFailed(let detail):
                return "Failed to connect to Photon printer: \(detail)"
            case .commandFailed(let command, let error):
                return "Command '\(command)' failed: \(error)"
            case .invalidResponse(let detail):
                return "Invalid printer response: \(detail)"
            case .timeout:
                return "Printer communication timed out"
            case .notPrinting:
                return "Printer is not currently printing"
            case .fileNotFound:
                return "File not found on printer"
            case .disconnected:
                return "Printer is disconnected"
            }
        }
    }

    /// Printer status parsed from getstatus command
    nonisolated enum PhotonStatus: Sendable {
        case idle
        case printing
        case paused
        case stopping
        case unknown(String)

        init(rawValue: String) {
            switch rawValue.lowercased() {
            case "stop", "idle":
                self = .idle
            case "print", "printing":
                self = .printing
            case "pause", "paused":
                self = .paused
            case "stopping":
                self = .stopping
            default:
                self = .unknown(rawValue)
            }
        }

        var displayText: String {
            switch self {
            case .idle: return "Idle"
            case .printing: return "Printing"
            case .paused: return "Paused"
            case .stopping: return "Stopping"
            case .unknown(let raw): return raw.capitalized
            }
        }

        var isOperational: Bool {
            switch self {
            case .idle, .printing, .paused, .stopping: return true
            case .unknown: return false
            }
        }
    }

    /// System information parsed from sysinfo command
    nonisolated struct PhotonSystemInfo: Sendable {
        let modelName: String
        let firmwareVersion: String
        let serialNumber: String
        let wifiNetwork: String
    }

    // MARK: - Constants

    /// Default TCP port for ACT protocol
    static let defaultPort = 6000

    /// Command timeout in seconds
    private let commandTimeout: TimeInterval = 5

    // MARK: - Connection Management

    /// Send a command and receive the response
    ///
    /// Opens a fresh TCP connection for each command to avoid stale connection issues.
    /// The Photon's TCP server handles concurrent connections.
    private func sendCommand(
        ipAddress: String,
        port: Int = PhotonPrinterService.defaultPort,
        command: String
    ) async throws -> [String] {
        // Create TCP connection
        let connection = NWConnection(
            host: NWEndpoint.Host(ipAddress),
            port: NWEndpoint.Port(integerLiteral: UInt16(port)),
            using: .tcp
        )

        return try await withCheckedThrowingContinuation { continuation in
            // Thread-safe guard to ensure continuation is resumed exactly once
            let resumeGuard = SendOnce()

            connection.stateUpdateHandler = { state in
                switch state {
                case .failed(let error):
                    if resumeGuard.tryAcquire() {
                        connection.cancel()
                        continuation.resume(
                            throwing: PhotonError.connectionFailed(error.localizedDescription))
                    }
                case .cancelled:
                    if resumeGuard.tryAcquire() {
                        continuation.resume(throwing: PhotonError.disconnected)
                    }
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInitiated))

            // Send command
            let commandData = Data((command + "\r\n").utf8)
            connection.send(
                content: commandData,
                completion: .contentProcessed { error in
                    if let error {
                        if resumeGuard.tryAcquire() {
                            connection.cancel()
                            continuation.resume(
                                throwing: PhotonError.connectionFailed(error.localizedDescription))
                        }
                        return
                    }

                    // Receive response
                    self.receiveResponse(connection: connection) { result in
                        if resumeGuard.tryAcquire() {
                            connection.cancel()
                            continuation.resume(with: result)
                        }
                    }
                })

            // Timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + self.commandTimeout) {
                if resumeGuard.tryAcquire() {
                    connection.cancel()
                    continuation.resume(throwing: PhotonError.timeout)
                }
            }
        }
    }

    /// Read response data until we see ",end" terminator
    private nonisolated func receiveResponse(
        connection: NWConnection,
        buffer: Data = Data(),
        completion: @escaping @Sendable (Result<[String], Error>) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
            content, _, isComplete, error in
            if let error {
                completion(.failure(PhotonError.connectionFailed(error.localizedDescription)))
                return
            }

            var accumulated = buffer
            if let content {
                accumulated.append(content)
            }

            // Check if we have a complete response (ends with ",end")
            let text = String(data: accumulated, encoding: .utf8) ?? ""
            if text.contains(",end") || isComplete {
                let parts = self.parseResponse(text)
                completion(.success(parts))
                return
            }

            // Keep reading
            self.receiveResponse(
                connection: connection, buffer: accumulated, completion: completion)
        }
    }

    /// Parse comma-delimited response into parts
    ///
    /// Response format: `command,value1,value2,...,end`
    /// Returns the values between the command echo and "end"
    nonisolated func parseResponse(_ raw: String) -> [String] {
        let cleaned =
            raw
            .replacingOccurrences(of: "\r\n", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespaces)

        let parts = cleaned.components(separatedBy: ",")

        // Remove first element (command echo) and last element ("end")
        guard parts.count >= 2 else { return [] }
        let values = Array(parts.dropFirst().dropLast())

        return values
    }

    // MARK: - Status Commands

    /// Get the current printer status
    ///
    /// Sends `getstatus` → receives `getstatus,<status>,end`
    /// Possible status values: stop, print, pause
    func getStatus(ipAddress: String, port: Int = defaultPort) async throws -> PhotonStatus {
        let response = try await sendCommand(
            ipAddress: ipAddress, port: port, command: "getstatus")

        guard let statusString = response.first else {
            throw PhotonError.invalidResponse("Empty status response")
        }

        return PhotonStatus(rawValue: statusString)
    }

    /// Get system information
    ///
    /// Sends `sysinfo` → receives `sysinfo,<model>,<firmware>,<serial>,<wifi>,end`
    /// Example: `sysinfo,Photon Mono X 6K,V0.2.2,00001A9F00030034,NetworkName,end`
    func getSystemInfo(ipAddress: String, port: Int = defaultPort) async throws
        -> PhotonSystemInfo
    {
        let response = try await sendCommand(
            ipAddress: ipAddress, port: port, command: "sysinfo")

        guard response.count >= 4 else {
            throw PhotonError.invalidResponse(
                "Expected 4 fields in sysinfo, got \(response.count)")
        }

        return PhotonSystemInfo(
            modelName: response[0],
            firmwareVersion: response[1],
            serialNumber: response[2],
            wifiNetwork: response[3]
        )
    }

    /// Get the connected WiFi network name
    ///
    /// Sends `getwifi` → receives `getwifi,<ssid>,end`
    func getWifiNetwork(ipAddress: String, port: Int = defaultPort) async throws -> String {
        let response = try await sendCommand(
            ipAddress: ipAddress, port: port, command: "getwifi")

        guard let ssid = response.first else {
            throw PhotonError.invalidResponse("Empty wifi response")
        }

        return ssid
    }

    // MARK: - Print Control

    /// Pause the current print job
    ///
    /// Sends `gopause` → receives `gopause,ok,end` or `gopause,ERROR1,end`
    func pausePrint(ipAddress: String, port: Int = defaultPort) async throws {
        let response = try await sendCommand(
            ipAddress: ipAddress, port: port, command: "gopause")

        if let result = response.first, result.hasPrefix("ERROR") {
            throw PhotonError.notPrinting
        }
    }

    /// Resume a paused print job
    ///
    /// Sends `goresume` → receives `goresume,ok,end` or `goresume,ERROR1,end`
    func resumePrint(ipAddress: String, port: Int = defaultPort) async throws {
        let response = try await sendCommand(
            ipAddress: ipAddress, port: port, command: "goresume")

        if let result = response.first, result.hasPrefix("ERROR") {
            throw PhotonError.notPrinting
        }
    }

    /// Stop the current print job
    ///
    /// Sends `gostop` → receives `gostop,ok,end` or `gostop,ERROR1,end`
    func stopPrint(ipAddress: String, port: Int = defaultPort) async throws {
        let response = try await sendCommand(
            ipAddress: ipAddress, port: port, command: "gostop")

        if let result = response.first, result.hasPrefix("ERROR") {
            throw PhotonError.notPrinting
        }
    }

    /// Start printing a file
    ///
    /// Sends `goprint,<filename>` → receives `goprint,ok,end` or `goprint,ERROR2,end`
    func startPrint(
        ipAddress: String, port: Int = defaultPort, filename: String
    ) async throws {
        let response = try await sendCommand(
            ipAddress: ipAddress, port: port, command: "goprint,\(filename)")

        if let result = response.first, result.hasPrefix("ERROR") {
            if result == "ERROR2" {
                throw PhotonError.fileNotFound
            }
            throw PhotonError.commandFailed(command: "goprint", error: result)
        }
    }

    // MARK: - Connection Testing

    /// Test if a Photon printer is reachable at the given address
    ///
    /// Attempts to connect and run `getstatus` — if it succeeds, the printer is online.
    func testConnection(ipAddress: String, port: Int = defaultPort) async throws -> Bool {
        do {
            _ = try await getStatus(ipAddress: ipAddress, port: port)
            return true
        } catch {
            return false
        }
    }

    /// Get full printer status as a `PrinterStatus` compatible with the existing UI
    ///
    /// Combines `getstatus` and `sysinfo` into the shared `PrinterStatus` type
    /// used by `PrinterDetailView`.
    func getPrinterStatus(ipAddress: String, port: Int = defaultPort) async throws -> PrinterStatus
    {
        let status = try await getStatus(ipAddress: ipAddress, port: port)
        let sysInfo = try? await getSystemInfo(ipAddress: ipAddress, port: port)

        let statusText = status.displayText
        let isOperational = status.isOperational
        let isPrinting = status == .printing
        let isPaused = status == .paused
        let isIdle = status == .idle
        let modelName = sysInfo?.modelName

        return PrinterStatus(
            state: PrinterState(
                text: statusText,
                flags: StateFlags(
                    operational: isOperational,
                    printing: isPrinting,
                    paused: isPaused,
                    ready: isIdle
                )
            ),
            temperature: nil,  // Photon resin printers don't report temperatures via ACT
            printerName: modelName
        )
    }

    // MARK: - Discovery

    /// Probe a specific IP address to check if a Photon printer is listening on port 6000
    static func probe(ipAddress: String, port: Int = defaultPort) async -> Bool {
        let connection = NWConnection(
            host: NWEndpoint.Host(ipAddress),
            port: NWEndpoint.Port(integerLiteral: UInt16(port)),
            using: .tcp
        )

        return await withCheckedContinuation { continuation in
            let resumeGuard = SendOnce()

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resumeGuard.tryAcquire() {
                        connection.cancel()
                        continuation.resume(returning: true)
                    }
                case .failed, .cancelled:
                    if resumeGuard.tryAcquire() {
                        connection.cancel()
                        continuation.resume(returning: false)
                    }
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .utility))

            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if resumeGuard.tryAcquire() {
                    connection.cancel()
                    continuation.resume(returning: false)
                }
            }
        }
    }
}

// MARK: - Equatable conformance for PhotonStatus

nonisolated extension PhotonPrinterService.PhotonStatus: Equatable {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.printing, .printing): return true
        case (.paused, .paused): return true
        case (.stopping, .stopping): return true
        case (.unknown(let a), .unknown(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - Thread-Safe Continuation Guard

/// Ensures a checked continuation is resumed exactly once, even when
/// multiple threads race to complete it (e.g. state handler vs. timeout).
///
/// Uses `OSAtomicCompareAndSwap` semantics via `os_unfair_lock` for minimal overhead.
nonisolated final class SendOnce: @unchecked Sendable {
    nonisolated(unsafe) private var _sent = false
    private let lock = NSLock()

    nonisolated init() {}

    /// Attempt to acquire the single-use token.
    /// Returns `true` exactly once; all subsequent calls return `false`.
    nonisolated func tryAcquire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !_sent else { return false }
        _sent = true
        return true
    }
}
