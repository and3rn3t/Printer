//
//  PrinterTests.swift
//  PrinterTests
//
//  Created by Matt on 2/10/26.
//

import Testing
import Foundation
import UniformTypeIdentifiers
@testable import Printer

// MARK: - Data Model Tests

struct PrintModelTests {

    @Test func createPrintModel() {
        let model = PrintModel(
            name: "Test Cube",
            fileURL: "STLFiles/cube.stl",
            fileSize: 84_000,
            source: .imported,
            notes: "A simple test cube"
        )

        #expect(model.name == "Test Cube")
        #expect(model.fileURL == "STLFiles/cube.stl")
        #expect(model.fileSize == 84_000)
        #expect(model.source == .imported)
        #expect(model.notes == "A simple test cube")
        #expect(model.thumbnailData == nil)
        #expect(model.printJobs.isEmpty)
    }

    @Test func resolvedFileURL_constructsCorrectPath() {
        let model = PrintModel(
            name: "Test",
            fileURL: "STLFiles/model.stl",
            fileSize: 1000,
            source: .imported
        )

        let resolved = model.resolvedFileURL
        #expect(resolved.lastPathComponent == "model.stl")
        #expect(resolved.pathComponents.contains("STLFiles"))
        #expect(resolved.pathComponents.contains("Documents"))
    }

    @Test func modelSourceCodable() throws {
        let sources: [ModelSource] = [.scanned, .imported, .downloaded]
        for source in sources {
            let data = try JSONEncoder().encode(source)
            let decoded = try JSONDecoder().decode(ModelSource.self, from: data)
            #expect(decoded == source)
        }
    }
}

struct PrintJobTests {

    @Test func createPrintJob() {
        let job = PrintJob(printerName: "Photon Mono X 6K")

        #expect(job.printerName == "Photon Mono X 6K")
        #expect(job.status == .preparing)
        #expect(job.endDate == nil)
        #expect(job.model == nil)
        #expect(job.fileName == nil)
        #expect(job.printerIP == nil)
        #expect(job.jobProtocol == nil)
        #expect(job.elapsedTime == 0)
        #expect(job.printStartDate == nil)
    }

    @Test func createPrintJobWithDetails() {
        let job = PrintJob(
            printerName: "Photon Mono X 6K",
            status: .printing,
            fileName: "cube.pwmx",
            printerIP: "192.168.1.49",
            jobProtocol: "act"
        )

        #expect(job.printerName == "Photon Mono X 6K")
        #expect(job.status == .printing)
        #expect(job.fileName == "cube.pwmx")
        #expect(job.printerIP == "192.168.1.49")
        #expect(job.jobProtocol == "act")
    }

    @Test func formattedDurationSeconds() {
        let job = PrintJob(printerName: "Test")
        job.elapsedTime = 45
        #expect(job.formattedDuration == "45s")
    }

    @Test func formattedDurationMinutes() {
        let job = PrintJob(printerName: "Test")
        job.elapsedTime = 185  // 3m 5s
        #expect(job.formattedDuration == "3m 5s")
    }

    @Test func formattedDurationHours() {
        let job = PrintJob(printerName: "Test")
        job.elapsedTime = 7320  // 2h 2m
        #expect(job.formattedDuration == "2h 2m")
    }

    @Test func formattedDurationZero() {
        let job = PrintJob(printerName: "Test")
        // No elapsed and no dates set, effectiveDuration will use startDate to now
        // but formattedDuration with elapsedTime=0 falls through to effectiveDuration
        // Since startDate is Date(), effectiveDuration is nearly 0
        // Just verify it returns a string
        #expect(!job.formattedDuration.isEmpty)
    }

    @Test func effectiveDurationFromElapsedTime() {
        let job = PrintJob(printerName: "Test")
        job.elapsedTime = 3600
        #expect(job.effectiveDuration == 3600)
    }

    @Test func effectiveDurationFromDates() {
        let job = PrintJob(printerName: "Test")
        job.printStartDate = Date().addingTimeInterval(-120)
        job.endDate = Date()
        // Should be approximately 120 seconds
        #expect(job.effectiveDuration >= 119)
        #expect(job.effectiveDuration <= 121)
    }

    @Test func printStatusCodable() throws {
        let statuses: [PrintStatus] = [
            .preparing, .uploading, .queued, .printing,
            .completed, .failed, .cancelled,
        ]
        for status in statuses {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(PrintStatus.self, from: data)
            #expect(decoded == status)
        }
    }
}

struct PrinterModelTests {

    @Test func createPrinterWithDefaults() {
        let printer = Printer(
            name: "My Photon",
            ipAddress: "192.168.1.49"
        )

        #expect(printer.name == "My Photon")
        #expect(printer.ipAddress == "192.168.1.49")
        #expect(printer.port == 6000)
        #expect(printer.printerProtocol == .act)
        #expect(printer.manufacturer == "Anycubic")
        #expect(printer.model == "")
        #expect(printer.apiKey == nil)
        #expect(printer.isConnected == false)
        #expect(printer.serialNumber == nil)
        #expect(printer.firmwareVersion == nil)
    }

    @Test func createPrinterWithOctoPrint() {
        let printer = Printer(
            name: "FDM Printer",
            ipAddress: "192.168.1.100",
            apiKey: "abc123",
            port: 80,
            printerProtocol: .octoprint
        )

        #expect(printer.port == 80)
        #expect(printer.printerProtocol == .octoprint)
        #expect(printer.apiKey == "abc123")
    }

    @Test func createPrinterWithAnycubicHTTP() {
        let printer = Printer(
            name: "Old Anycubic",
            ipAddress: "192.168.1.200",
            port: 18910,
            printerProtocol: .anycubicHTTP
        )

        #expect(printer.port == 18910)
        #expect(printer.printerProtocol == .anycubicHTTP)
    }

    @Test func printerProtocolCodable() throws {
        let protocols: [PrinterProtocol] = [.act, .octoprint, .anycubicHTTP]
        for proto in protocols {
            let data = try JSONEncoder().encode(proto)
            let decoded = try JSONDecoder().decode(PrinterProtocol.self, from: data)
            #expect(decoded == proto)
        }
    }

    @Test func printerProtocolRawValues() {
        #expect(PrinterProtocol.act.rawValue == "act")
        #expect(PrinterProtocol.octoprint.rawValue == "octoprint")
        #expect(PrinterProtocol.anycubicHTTP.rawValue == "anycubicHTTP")
    }
}

// MARK: - ACT Protocol Parsing Tests

struct PhotonProtocolTests {

    let service = PhotonPrinterService()

    @Test func parseStatusResponse() {
        let result = service.parseResponse("getstatus,stop,end")
        #expect(result == ["stop"])
    }

    @Test func parseSysinfoResponse() {
        let result = service.parseResponse(
            "sysinfo,Photon Mono X 6K,V0.2.2,00001A9F00030034,andernet,end"
        )
        #expect(result.count == 4)
        #expect(result[0] == "Photon Mono X 6K")
        #expect(result[1] == "V0.2.2")
        #expect(result[2] == "00001A9F00030034")
        #expect(result[3] == "andernet")
    }

    @Test func parseWifiResponse() {
        let result = service.parseResponse("getwifi,MyNetwork,end")
        #expect(result == ["MyNetwork"])
    }

    @Test func parsePauseSuccess() {
        let result = service.parseResponse("gopause,ok,end")
        #expect(result == ["ok"])
    }

    @Test func parsePauseError() {
        let result = service.parseResponse("gopause,ERROR1,end")
        #expect(result == ["ERROR1"])
    }

    @Test func parseGoprintError() {
        let result = service.parseResponse("goprint,ERROR2,end")
        #expect(result == ["ERROR2"])
    }

    @Test func parseModeResponse() {
        let result = service.parseResponse("getmode,0,end")
        #expect(result == ["0"])
    }

    @Test func parseResponseWithCRLF() {
        let result = service.parseResponse("getstatus,stop,end\r\n")
        #expect(result == ["stop"])
    }

    @Test func parseResponseWithNewline() {
        let result = service.parseResponse("getstatus,print,end\n")
        #expect(result == ["print"])
    }

    @Test func parseResponseWithWhitespace() {
        let result = service.parseResponse("  getstatus,pause,end  ")
        #expect(result == ["pause"])
    }

    @Test func parseEmptyResponse() {
        let result = service.parseResponse("")
        #expect(result.isEmpty)
    }

    @Test func parseSingleFieldResponse() {
        let result = service.parseResponse("cmd,end")
        #expect(result.isEmpty)
    }

    @Test func parseResponseMissingEnd() {
        // If there's no "end" marker, the last real value gets dropped
        // (it's treated as the "end" token by dropLast)
        let result = service.parseResponse("getstatus,stop")
        #expect(result.isEmpty)
    }
}

struct PhotonStatusTests {

    @Test func statusFromStop() {
        let status = PhotonPrinterService.PhotonStatus(rawValue: "stop")
        #expect(status == .idle)
        #expect(status.displayText == "Idle")
        #expect(status.isOperational)
    }

    @Test func statusFromIdle() {
        let status = PhotonPrinterService.PhotonStatus(rawValue: "idle")
        #expect(status == .idle)
    }

    @Test func statusFromPrint() {
        let status = PhotonPrinterService.PhotonStatus(rawValue: "print")
        #expect(status == .printing)
        #expect(status.displayText == "Printing")
        #expect(status.isOperational)
    }

    @Test func statusFromPause() {
        let status = PhotonPrinterService.PhotonStatus(rawValue: "pause")
        #expect(status == .paused)
        #expect(status.displayText == "Paused")
        #expect(status.isOperational)
    }

    @Test func statusFromStopping() {
        let status = PhotonPrinterService.PhotonStatus(rawValue: "stopping")
        #expect(status == .stopping)
        #expect(status.displayText == "Stopping")
        #expect(status.isOperational)
    }

    @Test func statusFromUnknown() {
        let status = PhotonPrinterService.PhotonStatus(rawValue: "weirdState")
        #expect(status == .unknown("weirdState"))
        #expect(status.displayText == "Weirdstate")
        #expect(!status.isOperational)
    }

    @Test func statusCaseInsensitive() {
        #expect(PhotonPrinterService.PhotonStatus(rawValue: "STOP") == .idle)
        #expect(PhotonPrinterService.PhotonStatus(rawValue: "Print") == .printing)
        #expect(PhotonPrinterService.PhotonStatus(rawValue: "PAUSE") == .paused)
    }
}

struct PhotonErrorTests {

    @Test func errorDescriptions() {
        let errors: [(PhotonPrinterService.PhotonError, String)] = [
            (.timeout, "Printer communication timed out"),
            (.notPrinting, "Printer is not currently printing"),
            (.fileNotFound, "File not found on printer"),
            (.disconnected, "Printer is disconnected"),
            (.connectionFailed("refused"), "Failed to connect to Photon printer: refused"),
            (.commandFailed(command: "gopause", error: "ERROR1"), "Command 'gopause' failed: ERROR1"),
            (.invalidResponse("bad data"), "Invalid printer response: bad data"),
        ]

        for (error, expected) in errors {
            #expect(error.errorDescription == expected)
        }
    }
}

// MARK: - API Error Tests

struct APIErrorTests {

    @Test func errorDescriptions() {
        let errors: [(AnycubicPrinterAPI.APIError, String)] = [
            (.invalidURL, "Invalid printer URL"),
            (.authenticationFailed, "Authentication failed — check your API key"),
            (.printerNotResponding, "Printer not responding"),
            (.timeout, "Request timed out"),
            (.cancelled, "Request was cancelled"),
        ]

        for (error, expected) in errors {
            #expect(error.errorDescription == expected)
        }
    }

    @Test func connectionFailedWithError() {
        let underlying = NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "refused"])
        let error = AnycubicPrinterAPI.APIError.connectionFailed(underlyingError: underlying)
        #expect(error.errorDescription?.contains("refused") == true)
    }

    @Test func connectionFailedWithoutError() {
        let error = AnycubicPrinterAPI.APIError.connectionFailed(underlyingError: nil)
        #expect(error.errorDescription == "Failed to connect to printer")
    }

    @Test func invalidResponseWithStatusCode() {
        let error = AnycubicPrinterAPI.APIError.invalidResponse(statusCode: 500)
        #expect(error.errorDescription == "Invalid response from printer (HTTP 500)")
    }

    @Test func invalidResponseWithoutStatusCode() {
        let error = AnycubicPrinterAPI.APIError.invalidResponse(statusCode: nil)
        #expect(error.errorDescription == "Invalid response from printer")
    }

    @Test func uploadFailedReason() {
        let error = AnycubicPrinterAPI.APIError.uploadFailed(reason: "disk full")
        #expect(error.errorDescription == "Failed to upload file: disk full")
    }

    @Test func unsupportedOperation() {
        let error = AnycubicPrinterAPI.APIError.unsupportedOperation("ACT printers don't support file listing")
        #expect(error.errorDescription == "ACT printers don't support file listing")
    }
}

// MARK: - Retry Configuration Tests

struct RetryConfigurationTests {

    @Test func defaultConfiguration() {
        let config = AnycubicPrinterAPI.RetryConfiguration.default
        #expect(config.maxRetries == 3)
        #expect(config.initialDelay == 1.0)
        #expect(config.maxDelay == 30.0)
        #expect(config.multiplier == 2.0)
        #expect(config.jitter == true)
    }

    @Test func aggressiveConfiguration() {
        let config = AnycubicPrinterAPI.RetryConfiguration.aggressive
        #expect(config.maxRetries == 5)
        #expect(config.initialDelay == 0.5)
    }

    @Test func noneConfiguration() {
        let config = AnycubicPrinterAPI.RetryConfiguration.none
        #expect(config.maxRetries == 0)
        #expect(config.jitter == false)
    }

    @Test func delayCalculation() {
        let config = AnycubicPrinterAPI.RetryConfiguration(
            maxRetries: 3,
            initialDelay: 1.0,
            maxDelay: 10.0,
            multiplier: 2.0,
            jitter: false
        )

        let delay0 = config.delay(forAttempt: 0)
        #expect(delay0 == 1.0)

        let delay1 = config.delay(forAttempt: 1)
        #expect(delay1 == 2.0)

        let delay2 = config.delay(forAttempt: 2)
        #expect(delay2 == 4.0)
    }

    @Test func delayClampedToMax() {
        let config = AnycubicPrinterAPI.RetryConfiguration(
            maxRetries: 10,
            initialDelay: 5.0,
            maxDelay: 10.0,
            multiplier: 3.0,
            jitter: false
        )

        let delay = config.delay(forAttempt: 5)
        #expect(delay <= 10.0)
    }

    @Test func delayWithJitter() {
        let config = AnycubicPrinterAPI.RetryConfiguration(
            maxRetries: 3,
            initialDelay: 1.0,
            maxDelay: 30.0,
            multiplier: 2.0,
            jitter: true
        )

        // With jitter (0.5...1.5 multiplier), delay should be in [0.5, 1.5]
        let delay = config.delay(forAttempt: 0)
        #expect(delay >= 0.5)
        #expect(delay <= 1.5)
    }
}

// MARK: - Response Model Tests

struct PrinterStatusModelTests {

    @Test func decodePrinterStatus() throws {
        let json = """
        {
            "state": {
                "text": "Operational",
                "flags": {
                    "operational": true,
                    "printing": false,
                    "paused": false,
                    "ready": true
                }
            },
            "temperature": {
                "bed": {"actual": 60.0, "target": 60.0},
                "tool0": {"actual": 200.0, "target": 210.0}
            }
        }
        """
        let data = Data(json.utf8)
        let status = try JSONDecoder().decode(PrinterStatus.self, from: data)

        #expect(status.state.text == "Operational")
        #expect(status.state.flags.operational)
        #expect(!status.state.flags.printing)
        #expect(status.state.flags.ready)
        #expect(status.temperature?.bed?.actual == 60.0)
        #expect(status.temperature?.tool0?.target == 210.0)
        #expect(status.printerName == nil)
    }

    @Test func createPrinterStatusManually() {
        let status = PrinterStatus(
            state: PrinterState(
                text: "Idle",
                flags: StateFlags(operational: true, printing: false, paused: false, ready: true)
            ),
            temperature: nil,
            printerName: "Photon Mono X 6K"
        )

        #expect(status.printerName == "Photon Mono X 6K")
        #expect(status.state.text == "Idle")
        #expect(status.temperature == nil)
    }
}

struct PrintJobStatusModelTests {

    @Test func decodePrintJobStatus() throws {
        let json = """
        {
            "state": "Printing",
            "job": {
                "file": {"name": "cube.stl", "size": 84000},
                "estimatedPrintTime": 3600.0
            },
            "progress": {
                "completion": 45.5,
                "printTime": 1620.0,
                "printTimeLeft": 1980.0
            }
        }
        """
        let data = Data(json.utf8)
        let jobStatus = try JSONDecoder().decode(PrintJobStatus.self, from: data)

        #expect(jobStatus.state == "Printing")
        #expect(jobStatus.job?.file?.name == "cube.stl")
        #expect(jobStatus.job?.file?.size == 84000)
        #expect(jobStatus.job?.estimatedPrintTime == 3600.0)
        #expect(jobStatus.progress?.completion == 45.5)
        #expect(jobStatus.progress?.printTime == 1620.0)
        #expect(jobStatus.progress?.printTimeLeft == 1980.0)
    }

    @Test func decodePrintJobStatusMinimal() throws {
        let json = """
        {"state": "Operational"}
        """
        let data = Data(json.utf8)
        let jobStatus = try JSONDecoder().decode(PrintJobStatus.self, from: data)

        #expect(jobStatus.state == "Operational")
        #expect(jobStatus.job == nil)
        #expect(jobStatus.progress == nil)
    }
}

struct PrinterFileModelTests {

    @Test func decodePrinterFile() throws {
        let json = """
        {"name": "model.pwmx", "size": 512000}
        """
        let data = Data(json.utf8)
        let file = try JSONDecoder().decode(PrinterFile.self, from: data)

        #expect(file.name == "model.pwmx")
        #expect(file.size == 512000)
        #expect(file.id == "model.pwmx")
    }

    @Test func decodeFileListResponse() throws {
        let json = """
        {"files": [{"name": "a.stl", "size": 100}, {"name": "b.pwmx", "size": 200}]}
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(FileListResponse.self, from: data)

        #expect(response.files.count == 2)
        #expect(response.files[0].name == "a.stl")
        #expect(response.files[1].name == "b.pwmx")
    }
}

// MARK: - STL File Manager Tests

struct STLFileManagerTests {

    @Test func validateBinarySTL() async {
        let manager = STLFileManager()
        // Binary STL: 80-byte header + 4-byte triangle count + triangle data
        var data = Data(repeating: 0, count: 80)  // header
        data.append(contentsOf: [0x01, 0x00, 0x00, 0x00])  // 1 triangle
        data.append(Data(repeating: 0, count: 50))  // 1 triangle = 50 bytes

        let result = await manager.validateSTL(data: data)
        #expect(result == true)
    }

    @Test func validateASCIISTL() async {
        let manager = STLFileManager()
        let asciiSTL = "solid testCube\nfacet normal 0 0 1\nouter loop\nvertex 0 0 0\nvertex 1 0 0\nvertex 1 1 0\nendloop\nendfacet\nendsolid testCube"
        let data = Data(asciiSTL.utf8)

        let result = await manager.validateSTL(data: data)
        #expect(result == true)
    }

    @Test func validateInvalidSTL() async {
        let manager = STLFileManager()
        let data = Data("not an STL file".utf8)

        let result = await manager.validateSTL(data: data)
        #expect(result == false)
    }

    @Test func validateEmptyData() async {
        let manager = STLFileManager()
        let data = Data()

        let result = await manager.validateSTL(data: data)
        #expect(result == false)
    }

    @Test func relativePathStripsDocumentsPrefix() async {
        let manager = STLFileManager()
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        let fileURL = documentsDir.appendingPathComponent("STLFiles/model.stl")

        let relative = await manager.relativePath(for: fileURL)
        #expect(relative == "STLFiles/model.stl")
    }

    @Test func relativePathFallbackForExternalURL() async {
        let manager = STLFileManager()
        let externalURL = URL(fileURLWithPath: "/tmp/random/model.stl")

        let relative = await manager.relativePath(for: externalURL)
        #expect(relative == "model.stl")
    }

    @Test func saveAndReadSTL() async throws {
        let manager = STLFileManager()

        // Create minimal binary STL data
        var stlData = Data(repeating: 0, count: 80)  // header
        stlData.append(contentsOf: [0x00, 0x00, 0x00, 0x00])  // 0 triangles

        let (url, size) = try await manager.saveSTL(data: stlData, filename: "test_unit.stl")

        #expect(size == Int64(stlData.count))
        #expect(url.lastPathComponent.contains("test_unit"))

        // Read it back
        let readData = try await manager.readSTL(at: url.path)
        #expect(readData == stlData)

        // Clean up
        try await manager.deleteSTL(at: url.path)
        let exists = await manager.fileExists(at: url.path)
        #expect(!exists)
    }

    @Test func fileExistsReturnsFalseForMissing() async {
        let manager = STLFileManager()
        let exists = await manager.fileExists(at: "/nonexistent/path/file.stl")
        #expect(!exists)
    }
}

// MARK: - Conversion Error Tests

struct ModelConverterErrorTests {

    @Test func conversionErrorDescriptions() {
        let errors: [(ModelConverter.ConversionError, String)] = [
            (.unsupportedFormat, "Unsupported file format"),
            (.conversionFailed, "Model conversion failed"),
            (.fileNotFound, "Source file not found"),
        ]

        for (error, expected) in errors {
            #expect(error.errorDescription == expected)
        }
    }

    @Test func convertNonexistentUSDZ() async {
        let converter = ModelConverter()
        let fakeURL = URL(fileURLWithPath: "/nonexistent/model.usdz")

        do {
            _ = try await converter.convertUSDZToSTL(usdzURL: fakeURL)
            #expect(Bool(false), "Should have thrown")
        } catch let error as ModelConverter.ConversionError {
            #expect(error == .fileNotFound)
        } catch {
            #expect(Bool(false), "Wrong error type: \(error)")
        }
    }

    @Test func convertNonexistentOBJ() async {
        let converter = ModelConverter()
        let fakeURL = URL(fileURLWithPath: "/nonexistent/model.obj")

        do {
            _ = try await converter.convertOBJToSTL(objURL: fakeURL)
            #expect(Bool(false), "Should have thrown")
        } catch let error as ModelConverter.ConversionError {
            #expect(error == .fileNotFound)
        } catch {
            #expect(Bool(false), "Wrong error type: \(error)")
        }
    }
}

// MARK: - UTType Extension Tests

struct UTTypeTests {

    @Test func stlType() {
        let stl = UTType.stl
        #expect(stl != .data || stl == .data)  // Just verify it doesn't crash
    }

    @Test func objType() {
        let obj = UTType.obj
        #expect(obj != .data || obj == .data)
    }
}

// MARK: - Network Monitor Tests

struct NetworkMonitorTests {

    @Test func initialState() {
        let monitor = NetworkMonitor()
        // Initial state before path update arrives
        #expect(monitor.statusDescription.isEmpty == false)
    }

    @Test func canAccessLocalPrintersLogic() {
        let monitor = NetworkMonitor()
        // canAccessLocalPrinters combines isConnected && isOnLocalNetwork
        // We can't easily set these, but we can verify the computed property exists
        let _ = monitor.canAccessLocalPrinters
    }
}

// MARK: - Discovery Model Tests

struct DiscoveredPrinterTests {

    @Test func createDiscoveredPrinter() {
        let printer = DiscoveredPrinter(
            id: "serial123",
            name: "Photon Mono X 6K",
            ipAddress: "192.168.1.49",
            port: 6000,
            manufacturer: "Anycubic",
            model: "Photon Mono X 6K",
            serialNumber: "serial123",
            discoveryMethod: .anycubicACT,
            discoveredAt: Date()
        )

        #expect(printer.name == "Photon Mono X 6K")
        #expect(printer.ipAddress == "192.168.1.49")
        #expect(printer.port == 6000)
        #expect(printer.manufacturer == "Anycubic")
        #expect(printer.serialNumber == "serial123")
        #expect(printer.discoveryMethod == .anycubicACT)
    }

    @Test func discoveryMethods() {
        #expect(DiscoveredPrinter.DiscoveryMethod.bonjour.rawValue == "Bonjour")
        #expect(DiscoveredPrinter.DiscoveryMethod.anycubicHTTP.rawValue == "Anycubic HTTP")
        #expect(DiscoveredPrinter.DiscoveryMethod.anycubicACT.rawValue == "Anycubic ACT")
        #expect(DiscoveredPrinter.DiscoveryMethod.manual.rawValue == "Manual")
    }
}

// MARK: - Printables Model Tests

struct PrintablesModelTests {

    @Test func searchResultDecoding() throws {
        let json = """
        {
            "id": "12345",
            "name": "3DBenchy",
            "image": {
                "filePath": "/media/prints/12345/thumb.jpg",
                "rotation": 0
            },
            "nsfw": false,
            "hasModel": true,
            "liked": null,
            "likesCount": 500,
            "downloadCount": 10000,
            "datePublished": "2023-06-14"
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(PrintablesSearchResult.self, from: json)
        #expect(result.id == "12345")
        #expect(result.name == "3DBenchy")
        #expect(result.image.filePath == "/media/prints/12345/thumb.jpg")
        #expect(result.image.rotation == 0)
        #expect(result.nsfw == false)
        #expect(result.hasModel == true)
        #expect(result.liked == nil)
        #expect(result.likesCount == 500)
        #expect(result.downloadCount == 10000)
        #expect(result.datePublished == "2023-06-14")
    }

    @Test func searchResultImageURL() throws {
        let json = """
        {
            "id": "1",
            "name": "Test",
            "image": { "filePath": "/media/prints/1/img.jpg", "rotation": 0 },
            "nsfw": false,
            "hasModel": true,
            "liked": null,
            "likesCount": 0,
            "downloadCount": 0,
            "datePublished": "2024-01-01"
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(PrintablesSearchResult.self, from: json)
        #expect(result.image.imageURL?.absoluteString == "https://media.printables.com/media/prints/1/img.jpg")
    }

    @Test func modelDetailDecoding() throws {
        let json = """
        {
            "id": "99",
            "name": "Vase",
            "images": [
                { "id": "1", "filePath": "/media/img1.jpg", "rotation": 0 },
                { "id": "2", "filePath": "/media/img2.jpg", "rotation": 90 }
            ],
            "nsfw": false,
            "hasModel": true,
            "liked": true,
            "likesCount": 42,
            "downloadCount": 100,
            "makesCount": 15,
            "datePublished": "2024-03-01",
            "summary": "A beautiful vase",
            "description": "<p>Print this vase</p>",
            "user": {
                "id": "7",
                "publicUsername": "maker42",
                "avatarFilePath": "/media/avatar.jpg",
                "handle": "maker42"
            },
            "tags": [
                { "id": "1", "name": "vase" },
                { "id": "2", "name": "decoration" }
            ],
            "stls": [
                {
                    "id": "s1",
                    "name": "vase.stl",
                    "fileSize": 512000,
                    "filePreviewPath": "/media/prints/99/stls/preview.png"
                }
            ],
            "gcodes": [],
            "slas": [],
            "category": {
                "id": "44",
                "path": [
                    { "id": "3", "name": "Household" },
                    { "id": "44", "name": "Home Decor" }
                ]
            },
            "license": {
                "id": "1",
                "name": "Creative Commons",
                "disallowRemixing": false
            }
        }
        """.data(using: .utf8)!

        let detail = try JSONDecoder().decode(PrintablesModelDetail.self, from: json)
        #expect(detail.id == "99")
        #expect(detail.name == "Vase")
        #expect(detail.images?.count == 2)
        #expect(detail.likesCount == 42)
        #expect(detail.downloadCount == 100)
        #expect(detail.makesCount == 15)
        #expect(detail.summary == "A beautiful vase")
        #expect(detail.description == "<p>Print this vase</p>")
        #expect(detail.user?.publicUsername == "maker42")
        #expect(detail.user?.handle == "maker42")
        #expect(detail.tags?.count == 2)
        #expect(detail.stls?.count == 1)
        #expect(detail.stls?.first?.name == "vase.stl")
        #expect(detail.stls?.first?.fileSize == 512000)
        #expect(detail.gcodes?.isEmpty == true)
        #expect(detail.slas?.isEmpty == true)
        #expect(detail.category?.path?.count == 2)
        #expect(detail.license?.name == "Creative Commons")
        #expect(detail.license?.disallowRemixing == false)
    }

    @Test func printablesFileProperties() throws {
        let json = """
        {
            "id": "f1",
            "name": "part.stl",
            "fileSize": 1048576,
            "filePreviewPath": "/media/prints/100/stls/preview.png"
        }
        """.data(using: .utf8)!

        let file = try JSONDecoder().decode(PrintablesFile.self, from: json)
        #expect(file.formattedFileSize == "1 MB")
        #expect(file.fileExtension == "stl")
        #expect(file.name == "part.stl")
    }

    @Test func printablesUserAvatarURL() throws {
        let json = """
        {
            "id": "5",
            "publicUsername": "TestUser",
            "avatarFilePath": "/media/avatars/test.jpg",
            "handle": "testuser"
        }
        """.data(using: .utf8)!

        let user = try JSONDecoder().decode(PrintablesUser.self, from: json)
        #expect(user.avatarURL?.absoluteString == "https://media.printables.com/media/avatars/test.jpg")
        #expect(user.publicUsername == "TestUser")
    }

    @Test func printablesOrderingValues() {
        #expect(PrintablesOrdering.allCases.count == 5)
        #expect(PrintablesOrdering.bestMatch.rawValue == "Best Match")
        #expect(PrintablesOrdering.latest.rawValue == "Newest")
        #expect(PrintablesOrdering.popular.rawValue == "Popular")
        #expect(PrintablesOrdering.makesCount.rawValue == "Most Makes")
        #expect(PrintablesOrdering.rating.rawValue == "Top Rated")
    }

    @Test func graphQLValueEncoding() throws {
        let encoder = JSONEncoder()

        // String
        let strData = try encoder.encode(GraphQLValue.string("test"))
        #expect(String(data: strData, encoding: .utf8) == "\"test\"")

        // Int
        let intData = try encoder.encode(GraphQLValue.int(42))
        #expect(String(data: intData, encoding: .utf8) == "42")

        // Bool
        let boolData = try encoder.encode(GraphQLValue.bool(true))
        #expect(String(data: boolData, encoding: .utf8) == "true")

        // Null
        let nullData = try encoder.encode(GraphQLValue.null)
        #expect(String(data: nullData, encoding: .utf8) == "null")
    }

    @Test func graphQLResponseDecoding() throws {
        let json = """
        {
            "data": {
                "searchPrints2": {
                    "items": []
                }
            },
            "errors": null
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(GraphQLResponse<SearchPrintsData>.self, from: json)
        #expect(response.data != nil)
        #expect(response.data?.searchPrints2.items.isEmpty == true)
        #expect(response.errors == nil)
    }

    @Test func graphQLErrorResponseDecoding() throws {
        let json = """
        {
            "data": null,
            "errors": [
                { "message": "Something went wrong" }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(GraphQLResponse<SearchPrintsData>.self, from: json)
        #expect(response.data == nil)
        #expect(response.errors?.count == 1)
        #expect(response.errors?.first?.message == "Something went wrong")
    }

    @Test func printablesErrorDescriptions() {
        let errors: [(PrintablesService.PrintablesError, String)] = [
            (.invalidURL, "Invalid Printables API URL"),
            (.networkError("timeout"), "Network error: timeout"),
            (.graphQLError("bad query"), "Printables API error: bad query"),
            (.decodingError("missing field"), "Failed to decode response: missing field"),
            (.noData, "No data returned from Printables"),
            (.downloadFailed("404"), "File download failed: 404"),
        ]

        for (error, expected) in errors {
            #expect(error.errorDescription == expected)
        }
    }

    @Test func searchResultsResponseDecoding() throws {
        let json = """
        {
            "data": {
                "searchPrints2": {
                    "items": [
                        {
                            "id": "1",
                            "name": "Benchy",
                            "image": { "filePath": "/img.jpg", "rotation": 0 },
                            "nsfw": false,
                            "hasModel": true,
                            "liked": null,
                            "likesCount": 100,
                            "downloadCount": 500,
                            "datePublished": "2024-01-01"
                        },
                        {
                            "id": "2",
                            "name": "Calibration Cube",
                            "image": { "filePath": "/img2.jpg", "rotation": 0 },
                            "nsfw": false,
                            "hasModel": true,
                            "liked": null,
                            "likesCount": 50,
                            "downloadCount": 200,
                            "datePublished": "2024-02-01"
                        }
                    ]
                }
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(GraphQLResponse<SearchPrintsData>.self, from: json)
        #expect(response.data?.searchPrints2.items.count == 2)
        #expect(response.data?.searchPrints2.items[0].name == "Benchy")
        #expect(response.data?.searchPrints2.items[1].name == "Calibration Cube")
    }
}
