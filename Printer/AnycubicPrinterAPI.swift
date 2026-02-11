//
//  AnycubicPrinterAPI.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import Foundation

/// Handles communication with Anycubic 3D printers via their web interface
actor AnycubicPrinterAPI {
    
    enum APIError: LocalizedError {
        case invalidURL
        case connectionFailed
        case uploadFailed
        case authenticationFailed
        case printerNotResponding
        case invalidResponse
        
        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid printer URL"
            case .connectionFailed:
                return "Failed to connect to printer"
            case .uploadFailed:
                return "Failed to upload file"
            case .authenticationFailed:
                return "Authentication failed"
            case .printerNotResponding:
                return "Printer not responding"
            case .invalidResponse:
                return "Invalid response from printer"
            }
        }
    }
    
    private let urlSession: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.urlSession = URLSession(configuration: config)
    }
    
    // MARK: - Connection
    
    /// Test connection to printer
    func testConnection(ipAddress: String) async throws -> Bool {
        let urlString = "http://\(ipAddress)/api/version"
        
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }
        
        do {
            let (_, response) = try await urlSession.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            return httpResponse.statusCode == 200
        } catch {
            throw APIError.connectionFailed
        }
    }
    
    /// Get printer status
    func getPrinterStatus(ipAddress: String, apiKey: String?) async throws -> PrinterStatus {
        let urlString = "http://\(ipAddress)/api/printer"
        
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        if let apiKey = apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        }
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.printerNotResponding
        }
        
        let status = try JSONDecoder().decode(PrinterStatus.self, from: data)
        return status
    }
    
    // MARK: - File Upload
    
    /// Upload STL file to printer
    func uploadFile(
        ipAddress: String,
        apiKey: String?,
        fileURL: URL,
        filename: String,
        progress: @escaping (Double) -> Void
    ) async throws {
        let urlString = "http://\(ipAddress)/api/files/local"
        
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }
        
        // Read file data
        let fileData = try Data(contentsOf: fileURL)
        
        // Create multipart form data
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        if let apiKey = apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        }
        
        // Build multipart body
        var body = Data()
        
        // Add file data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        // Create upload task with progress tracking
        let (_, response) = try await urlSession.upload(for: request, from: body)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw APIError.uploadFailed
        }
        
        progress(1.0)
    }
    
    /// Start printing a file
    func startPrint(
        ipAddress: String,
        apiKey: String?,
        filename: String
    ) async throws {
        let urlString = "http://\(ipAddress)/api/files/local/\(filename)"
        
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let apiKey = apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        }
        
        let command = ["command": "select", "print": true]
        request.httpBody = try JSONSerialization.data(withJSONObject: command)
        
        let (_, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 204 else {
            throw APIError.invalidResponse
        }
    }
    
    // MARK: - File Management
    
    /// List files on printer
    func listFiles(ipAddress: String, apiKey: String?) async throws -> [PrinterFile] {
        let urlString = "http://\(ipAddress)/api/files"
        
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        if let apiKey = apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        }
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.printerNotResponding
        }
        
        let fileList = try JSONDecoder().decode(FileListResponse.self, from: data)
        return fileList.files
    }
}

// MARK: - Models

struct PrinterStatus: Codable {
    let state: PrinterState
    let temperature: Temperature?
    
    struct PrinterState: Codable {
        let text: String
        let flags: StateFlags
        
        struct StateFlags: Codable {
            let operational: Bool
            let printing: Bool
            let paused: Bool
            let ready: Bool
        }
    }
    
    struct Temperature: Codable {
        let bed: TemperatureData?
        let tool0: TemperatureData?
        
        struct TemperatureData: Codable {
            let actual: Double
            let target: Double
        }
    }
}

struct PrinterFile: Codable, Identifiable {
    let name: String
    let size: Int64?
    let date: Date?
    
    var id: String { name }
}

struct FileListResponse: Codable {
    let files: [PrinterFile]
}

struct UploadResponse: Codable {
    let files: FileInfo
    
    struct FileInfo: Codable {
        let local: FileDetail
        
        struct FileDetail: Codable {
            let name: String
            let origin: String
        }
    }
}
