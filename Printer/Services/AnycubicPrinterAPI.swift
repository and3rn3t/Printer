//
//  AnycubicPrinterAPI.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import Foundation

/// Handles communication with Anycubic 3D printers via their web interface
///
/// Supports three protocols:
/// - **ACT** (TCP port 6000): For Photon resin printers — delegates to `PhotonPrinterService`
/// - **OctoPrint** (HTTP port 80): REST API for FDM printers with OctoPrint firmware
/// - **Anycubic HTTP** (port 18910): Native Anycubic HTTP discovery/status endpoint
///
/// Includes retry logic with exponential backoff, real upload progress tracking,
/// and connection health monitoring.
actor AnycubicPrinterAPI {

    // MARK: - Errors

    enum APIError: LocalizedError {
        case invalidURL
        case connectionFailed(underlyingError: Error?)
        case uploadFailed(reason: String)
        case authenticationFailed
        case printerNotResponding
        case invalidResponse(statusCode: Int?)
        case timeout
        case cancelled
        case maxRetriesExceeded(lastError: Error)
        case unsupportedOperation(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid printer URL"
            case .connectionFailed(let error):
                if let error {
                    return "Failed to connect to printer: \(error.localizedDescription)"
                }
                return "Failed to connect to printer"
            case .uploadFailed(let reason):
                return "Failed to upload file: \(reason)"
            case .authenticationFailed:
                return "Authentication failed — check your API key"
            case .printerNotResponding:
                return "Printer not responding"
            case .invalidResponse(let statusCode):
                if let code = statusCode {
                    return "Invalid response from printer (HTTP \(code))"
                }
                return "Invalid response from printer"
            case .timeout:
                return "Request timed out"
            case .cancelled:
                return "Request was cancelled"
            case .maxRetriesExceeded(let lastError):
                return "Failed after multiple retries: \(lastError.localizedDescription)"
            case .unsupportedOperation(let detail):
                return detail
            }
        }
    }

    // MARK: - Retry Configuration

    /// Configuration for retry behavior
    struct RetryConfiguration: Sendable {
        var maxRetries: Int
        var initialDelay: TimeInterval
        var maxDelay: TimeInterval
        var multiplier: Double
        var jitter: Bool

        static let `default` = RetryConfiguration(
            maxRetries: 3,
            initialDelay: 1.0,
            maxDelay: 30.0,
            multiplier: 2.0,
            jitter: true
        )

        static let aggressive = RetryConfiguration(
            maxRetries: 5,
            initialDelay: 0.5,
            maxDelay: 60.0,
            multiplier: 2.0,
            jitter: true
        )

        static let none = RetryConfiguration(
            maxRetries: 0,
            initialDelay: 0,
            maxDelay: 0,
            multiplier: 1.0,
            jitter: false
        )

        /// Calculate delay for a given attempt number
        func delay(forAttempt attempt: Int) -> TimeInterval {
            let baseDelay = min(initialDelay * pow(multiplier, Double(attempt)), maxDelay)
            if jitter {
                return baseDelay * Double.random(in: 0.5...1.5)
            }
            return baseDelay
        }
    }

    // MARK: - Properties

    private let urlSession: URLSession
    private var uploadDelegates: [UUID: UploadProgressDelegate] = [:]
    
    /// ACT protocol service for Photon resin printers
    private let photonService = PhotonPrinterService()

    // MARK: - Initialization

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = true
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Retry Logic

    /// Execute a request with automatic retry on failure
    private func withRetry<T>(
        config: RetryConfiguration = .default,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error = APIError.connectionFailed(underlyingError: nil)

        for attempt in 0...config.maxRetries {
            do {
                return try await operation()
            } catch is CancellationError {
                throw APIError.cancelled
            } catch {
                lastError = error

                // Don't retry auth failures or invalid URLs
                if let apiError = error as? APIError {
                    switch apiError {
                    case .authenticationFailed, .invalidURL, .cancelled:
                        throw error
                    default:
                        break
                    }
                }

                if attempt < config.maxRetries {
                    let delay = config.delay(forAttempt: attempt)
                    try await Task.sleep(for: .seconds(delay))
                }
            }
        }

        throw APIError.maxRetriesExceeded(lastError: lastError)
    }

    // MARK: - Connection

    /// Test connection to printer with retry
    ///
    /// Tries ACT protocol (TCP port 6000) first, then falls back to HTTP.
    func testConnection(ipAddress: String, retryConfig: RetryConfiguration = .default) async throws
        -> Bool
    {
        // Try ACT protocol first (Photon resin printers)
        if try await photonService.testConnection(ipAddress: ipAddress) {
            return true
        }
        
        // Fall back to HTTP-based protocols
        return try await withRetry(config: retryConfig) { [urlSession] in
            // Try Anycubic native endpoint first
            if let anycubicURL = URL(string: "http://\(ipAddress):18910/info") {
                var request = URLRequest(url: anycubicURL)
                request.timeoutInterval = 5

                if let (_, response) = try? await urlSession.data(for: request),
                    let httpResponse = response as? HTTPURLResponse,
                    httpResponse.statusCode == 200
                {
                    return true
                }
            }

            // Fall back to OctoPrint-compatible endpoint
            guard let url = URL(string: "http://\(ipAddress)/api/version") else {
                throw APIError.invalidURL
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = 10

            let (_, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse(statusCode: nil)
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw APIError.authenticationFailed
            }

            return httpResponse.statusCode == 200
        }
    }

    // MARK: - Printer Status

    /// Get printer status with retry
    ///
    /// For Photon printers (ACT protocol), delegates to `PhotonPrinterService`.
    /// For HTTP printers, tries Anycubic native then OctoPrint.
    func getPrinterStatus(
        ipAddress: String,
        apiKey: String?,
        protocol printerProtocol: PrinterProtocol = .act
    ) async throws -> PrinterStatus {
        // ACT protocol path — Photon resin printers
        if printerProtocol == .act {
            return try await photonService.getPrinterStatus(ipAddress: ipAddress)
        }
        
        // HTTP protocol paths
        return try await withRetry { [urlSession] in
            // Try Anycubic native endpoint first
            if let nativeStatus = try? await Self.getAnycubicNativeStatus(
                ipAddress: ipAddress,
                urlSession: urlSession
            ) {
                return nativeStatus
            }

            // Fall back to OctoPrint API
            guard let url = URL(string: "http://\(ipAddress)/api/printer") else {
                throw APIError.invalidURL
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            if let apiKey {
                request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
            }

            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse(statusCode: nil)
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw APIError.authenticationFailed
            }

            guard httpResponse.statusCode == 200 else {
                throw APIError.printerNotResponding
            }

            return try JSONDecoder().decode(PrinterStatus.self, from: data)
        }
    }

    /// Get printer status from Anycubic native HTTP endpoint
    private static func getAnycubicNativeStatus(
        ipAddress: String,
        urlSession: URLSession
    ) async throws -> PrinterStatus {
        guard let url = URL(string: "http://\(ipAddress):18910/info") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            throw APIError.printerNotResponding
        }

        // Parse Anycubic native response into our PrinterStatus model
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let state = json?["state"] as? String ?? "unknown"
        let modelName = json?["modelName"] as? String ?? "Anycubic Printer"

        return PrinterStatus(
            state: PrinterState(
                text: state.isEmpty ? "operational" : state,
                flags: StateFlags(
                    operational: true,
                    printing: state == "printing",
                    paused: state == "paused",
                    ready: state != "printing" && state != "paused"
                )
            ),
            temperature: nil,
            printerName: modelName
        )
    }

    // MARK: - File Upload with Progress

    /// Upload a file to the printer with real progress tracking
    ///
    /// Uses URLSessionTaskDelegate for incremental upload progress reporting,
    /// unlike the previous implementation which only reported completion.
    func uploadFile(
        ipAddress: String,
        apiKey: String?,
        fileURL: URL,
        filename: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try await withRetry(config: .aggressive) { [self] in
            try await self.performUpload(
                ipAddress: ipAddress,
                apiKey: apiKey,
                fileURL: fileURL,
                filename: filename,
                progress: progress
            )
        }
    }

    /// Internal upload implementation with real progress tracking
    private func performUpload(
        ipAddress: String,
        apiKey: String?,
        fileURL: URL,
        filename: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let url = URL(string: "http://\(ipAddress)/api/files/local") else {
            throw APIError.invalidURL
        }

        // Read file data
        let fileData: Data
        do {
            fileData = try Data(contentsOf: fileURL)
        } catch {
            throw APIError.uploadFailed(reason: "Cannot read file: \(error.localizedDescription)")
        }

        // Create multipart form data
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        if let apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        }

        // Build multipart body
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        // Create a delegate for progress tracking
        let taskID = UUID()
        let delegate = UploadProgressDelegate(progress: progress)
        uploadDelegates[taskID] = delegate

        defer {
            uploadDelegates.removeValue(forKey: taskID)
        }

        // Create a URLSession with the delegate for this upload
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        defer {
            session.invalidateAndCancel()
        }

        let (_, response) = try await session.upload(for: request, from: body)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(statusCode: nil)
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw APIError.authenticationFailed
        }

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw APIError.uploadFailed(reason: "Server returned HTTP \(httpResponse.statusCode)")
        }

        progress(1.0)
    }

    // MARK: - Print Control

    /// Start printing a file
    func startPrint(
        ipAddress: String,
        apiKey: String?,
        filename: String,
        protocol printerProtocol: PrinterProtocol = .act
    ) async throws {
        if printerProtocol == .act {
            try await photonService.startPrint(ipAddress: ipAddress, filename: filename)
            return
        }
        
        try await withRetry { [urlSession] in
            guard let url = URL(string: "http://\(ipAddress)/api/files/local/\(filename)") else {
                throw APIError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            if let apiKey {
                request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
            }

            let command: [String: Any] = ["command": "select", "print": true]
            request.httpBody = try JSONSerialization.data(withJSONObject: command)

            let (_, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 204
            else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode
                throw APIError.invalidResponse(statusCode: statusCode)
            }
        }
    }

    /// Pause current print job
    func pausePrint(
        ipAddress: String,
        apiKey: String?,
        protocol printerProtocol: PrinterProtocol = .act
    ) async throws {
        if printerProtocol == .act {
            try await photonService.pausePrint(ipAddress: ipAddress)
            return
        }
        try await sendJobCommand(
            ipAddress: ipAddress, apiKey: apiKey, command: "pause", action: "pause")
    }

    /// Resume paused print job
    func resumePrint(
        ipAddress: String,
        apiKey: String?,
        protocol printerProtocol: PrinterProtocol = .act
    ) async throws {
        if printerProtocol == .act {
            try await photonService.resumePrint(ipAddress: ipAddress)
            return
        }
        try await sendJobCommand(
            ipAddress: ipAddress, apiKey: apiKey, command: "pause", action: "resume")
    }

    /// Cancel current print job
    func cancelPrint(
        ipAddress: String,
        apiKey: String?,
        protocol printerProtocol: PrinterProtocol = .act
    ) async throws {
        if printerProtocol == .act {
            try await photonService.stopPrint(ipAddress: ipAddress)
            return
        }
        try await sendJobCommand(ipAddress: ipAddress, apiKey: apiKey, command: "cancel")
    }

    /// Send a job control command to the printer
    private func sendJobCommand(
        ipAddress: String,
        apiKey: String?,
        command: String,
        action: String? = nil
    ) async throws {
        try await withRetry(config: .default) { [urlSession] in
            guard let url = URL(string: "http://\(ipAddress)/api/job") else {
                throw APIError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            if let apiKey {
                request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
            }

            var body: [String: Any] = ["command": command]
            if let action {
                body["action"] = action
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (_, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 204 || httpResponse.statusCode == 200
            else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode
                throw APIError.invalidResponse(statusCode: statusCode)
            }
        }
    }

    // MARK: - Print Job Status

    /// Get current print job information
    func getJobStatus(ipAddress: String, apiKey: String?) async throws -> PrintJobStatus {
        try await withRetry { [urlSession] in
            guard let url = URL(string: "http://\(ipAddress)/api/job") else {
                throw APIError.invalidURL
            }

            var request = URLRequest(url: url)
            if let apiKey {
                request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
            }

            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200
            else {
                throw APIError.printerNotResponding
            }

            return try JSONDecoder().decode(PrintJobStatus.self, from: data)
        }
    }

    // MARK: - File Management

    /// List files on printer with retry
    func listFiles(ipAddress: String, apiKey: String?) async throws -> [PrinterFile] {
        try await withRetry { [urlSession] in
            guard let url = URL(string: "http://\(ipAddress)/api/files") else {
                throw APIError.invalidURL
            }

            var request = URLRequest(url: url)
            if let apiKey {
                request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
            }

            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200
            else {
                throw APIError.printerNotResponding
            }

            let fileList = try JSONDecoder().decode(FileListResponse.self, from: data)
            return fileList.files
        }
    }

    /// Delete a file from the printer
    func deleteFile(ipAddress: String, apiKey: String?, filename: String) async throws {
        try await withRetry { [urlSession] in
            guard let url = URL(string: "http://\(ipAddress)/api/files/local/\(filename)") else {
                throw APIError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"

            if let apiKey {
                request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
            }

            let (_, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 204 || httpResponse.statusCode == 200
            else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode
                throw APIError.invalidResponse(statusCode: statusCode)
            }
        }
    }

    // MARK: - Connection Health

    /// Check if printer is reachable (lightweight ping)
    func isReachable(ipAddress: String) async -> Bool {
        // Try ACT protocol first (fastest for Photon printers)
        if await PhotonPrinterService.probe(ipAddress: ipAddress) {
            return true
        }
        
        guard let url = URL(string: "http://\(ipAddress)/api/version") else {
            return false
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.httpMethod = "HEAD"

        do {
            let (_, response) = try await urlSession.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            // Also try Anycubic native endpoint
            guard let anycubicURL = URL(string: "http://\(ipAddress):18910/info") else {
                return false
            }

            var nativeRequest = URLRequest(url: anycubicURL)
            nativeRequest.timeoutInterval = 3

            do {
                let (_, response) = try await urlSession.data(for: nativeRequest)
                return (response as? HTTPURLResponse)?.statusCode == 200
            } catch {
                return false
            }
        }
    }
}

// MARK: - Upload Progress Delegate

/// URLSession delegate that tracks upload progress and reports it back
private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let progressHandler: @Sendable (Double) -> Void

    init(progress: @escaping @Sendable (Double) -> Void) {
        self.progressHandler = progress
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        progressHandler(min(progress, 0.99))  // Reserve 1.0 for completion confirmation
    }
}

// MARK: - Response Models

/// Printer status from the API
struct PrinterStatus: Codable, Sendable {
    let state: PrinterState
    let temperature: Temperature?
    let printerName: String?

    init(state: PrinterState, temperature: Temperature?, printerName: String? = nil) {
        self.state = state
        self.temperature = temperature
        self.printerName = printerName
    }

    enum CodingKeys: String, CodingKey {
        case state
        case temperature = "temperature"
        case printerName
    }
}

struct PrinterState: Codable, Sendable {
    let text: String
    let flags: StateFlags
}

struct StateFlags: Codable, Sendable {
    let operational: Bool
    let printing: Bool
    let paused: Bool
    let ready: Bool
}

struct Temperature: Codable, Sendable {
    let bed: TemperatureData?
    let tool0: TemperatureData?
}

struct TemperatureData: Codable, Sendable {
    let actual: Double
    let target: Double
}

/// Status of the current print job
struct PrintJobStatus: Codable, Sendable {
    let job: JobInfo?
    let progress: ProgressInfo?
    let state: String

    struct JobInfo: Codable, Sendable {
        let file: JobFile?
        let estimatedPrintTime: Double?

        struct JobFile: Codable, Sendable {
            let name: String?
            let size: Int64?
        }
    }

    struct ProgressInfo: Codable, Sendable {
        let completion: Double?
        let printTime: Double?
        let printTimeLeft: Double?
    }
}

/// A file stored on the printer
struct PrinterFile: Codable, Identifiable, Sendable {
    let name: String
    let size: Int64?
    let date: Date?

    var id: String { name }
}

/// Response wrapper for file list
struct FileListResponse: Codable, Sendable {
    let files: [PrinterFile]
}

/// Response from file upload
struct UploadResponse: Codable, Sendable {
    let files: FileInfo

    struct FileInfo: Codable, Sendable {
        let local: FileDetail

        struct FileDetail: Codable, Sendable {
            let name: String
            let origin: String
        }
    }
}
