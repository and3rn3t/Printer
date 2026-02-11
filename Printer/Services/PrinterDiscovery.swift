//
//  PrinterDiscovery.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import Foundation
import Network
import Observation

// MARK: - Discovered Printer Info

/// Represents a printer found during network discovery
struct DiscoveredPrinter: Identifiable, Hashable {
    let id: String
    let name: String
    let ipAddress: String
    let port: Int
    let manufacturer: String
    let model: String
    let serialNumber: String?
    let discoveryMethod: DiscoveryMethod
    let discoveredAt: Date
    
    enum DiscoveryMethod: String {
        case bonjour = "Bonjour"
        case anycubicHTTP = "Anycubic HTTP"
        case manual = "Manual"
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(ipAddress)
    }
    
    static func == (lhs: DiscoveredPrinter, rhs: DiscoveredPrinter) -> Bool {
        lhs.ipAddress == rhs.ipAddress
    }
}

// MARK: - Anycubic Discovery Response

/// Response from Anycubic printer HTTP discovery endpoint
struct AnycubicDiscoveryResponse: Codable {
    let modelId: String?
    let modelName: String?
    let deviceId: String?
    let cn: String?
    let token: String?
    let ctrlInfoUrl: String?
    let firmwareVersion: String?
    let ip: String?
}

// MARK: - Printer Discovery Service

/// Service for discovering 3D printers on the local network
///
/// Supports multiple discovery methods:
/// - Bonjour/mDNS for network service browsing
/// - Anycubic HTTP discovery for direct printer detection
/// - Subnet scanning for broader discovery
@Observable
final class PrinterDiscovery {
    
    // MARK: - Properties
    
    /// Currently discovered printers
    private(set) var discoveredPrinters: [DiscoveredPrinter] = []
    
    /// Whether discovery is currently running
    private(set) var isScanning: Bool = false
    
    /// Last error encountered during discovery
    private(set) var lastError: String?
    
    /// Progress of subnet scan (0.0 to 1.0)
    private(set) var scanProgress: Double = 0.0
    
    private var browser: NWBrowser?
    private var scanTask: Task<Void, Never>?
    
    // MARK: - Bonjour Discovery
    
    /// Common Bonjour service types for 3D printers
    private static let serviceTypes = [
        "_octoprint._tcp",
        "_http._tcp",
        "_ipp._tcp"
    ]
    
    /// Start Bonjour/mDNS discovery for network printers
    func startBonjourDiscovery() {
        stopDiscovery()
        isScanning = true
        lastError = nil
        
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        
        // Browse for HTTP services which printers often advertise
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_http._tcp", domain: nil)
        browser = NWBrowser(for: descriptor, using: parameters)
        
        browser?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    break
                case .failed(let error):
                    self?.lastError = "Bonjour discovery failed: \(error.localizedDescription)"
                    self?.isScanning = false
                case .cancelled:
                    self?.isScanning = false
                default:
                    break
                }
            }
        }
        
        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.processBrowseResults(results)
            }
        }
        
        browser?.start(queue: .global(qos: .userInitiated))
    }
    
    /// Process Bonjour browse results
    @MainActor
    private func processBrowseResults(_ results: Set<NWBrowser.Result>) {
        for result in results {
            if case .service(let name, let type, let domain, _) = result.endpoint {
                // Resolve the service to get IP address
                resolveService(name: name, type: type, domain: domain)
            }
        }
    }
    
    /// Resolve a Bonjour service to get its IP address
    private func resolveService(name: String, type: String, domain: String) {
        let endpoint = NWEndpoint.service(name: name, type: type, domain: domain, interface: nil)
        let parameters = NWParameters.tcp
        let connection = NWConnection(to: endpoint, using: parameters)
        
        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                if let innerEndpoint = connection.currentPath?.remoteEndpoint,
                   case .hostPort(let host, let port) = innerEndpoint {
                    let ipString: String
                    switch host {
                    case .ipv4(let addr):
                        ipString = "\(addr)"
                    case .ipv6(let addr):
                        ipString = "\(addr)"
                    default:
                        ipString = "\(host)"
                    }
                    
                    let printer = DiscoveredPrinter(
                        id: "\(ipString):\(port)",
                        name: name,
                        ipAddress: ipString,
                        port: Int(port.rawValue),
                        manufacturer: "Unknown",
                        model: "",
                        serialNumber: nil,
                        discoveryMethod: .bonjour,
                        discoveredAt: Date()
                    )
                    
                    Task { @MainActor in
                        self?.addDiscoveredPrinter(printer)
                    }
                }
                connection.cancel()
            }
        }
        
        connection.start(queue: .global(qos: .utility))
        
        // Cancel after timeout
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            connection.cancel()
        }
    }
    
    // MARK: - Anycubic HTTP Discovery
    
    /// Probe a specific IP address for an Anycubic printer
    /// Uses the Anycubic HTTP discovery endpoint at port 18910
    func probeAnycubicPrinter(ipAddress: String) async -> DiscoveredPrinter? {
        let urlString = "http://\(ipAddress):18910/info"
        
        guard let url = URL(string: urlString) else { return nil }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            
            let info = try JSONDecoder().decode(AnycubicDiscoveryResponse.self, from: data)
            
            return DiscoveredPrinter(
                id: info.deviceId ?? ipAddress,
                name: info.modelName ?? "Anycubic Printer",
                ipAddress: ipAddress,
                port: 18910,
                manufacturer: "Anycubic",
                model: info.modelName ?? "",
                serialNumber: info.cn,
                discoveryMethod: .anycubicHTTP,
                discoveredAt: Date()
            )
        } catch {
            return nil
        }
    }
    
    // MARK: - Subnet Scanning
    
    /// Scan the local subnet for Anycubic printers
    /// Probes common printer ports on the local /24 subnet
    func scanSubnet(baseIP: String? = nil) {
        stopDiscovery()
        isScanning = true
        lastError = nil
        scanProgress = 0.0
        
        scanTask = Task { [weak self] in
            guard let self else { return }
            
            // Determine base IP from provided value or try to detect
            let subnet: String
            if let baseIP = baseIP {
                let components = baseIP.split(separator: ".")
                if components.count == 4 {
                    subnet = components.dropLast().joined(separator: ".")
                } else {
                    subnet = "192.168.1"
                }
            } else {
                subnet = "192.168.1"
            }
            
            let totalHosts = 254
            var scannedCount = 0
            
            // Scan in batches for efficiency
            let batchSize = 20
            
            for batchStart in stride(from: 1, through: totalHosts, by: batchSize) {
                if Task.isCancelled { break }
                
                let batchEnd = min(batchStart + batchSize - 1, totalHosts)
                
                await withTaskGroup(of: DiscoveredPrinter?.self) { group in
                    for i in batchStart...batchEnd {
                        let ip = "\(subnet).\(i)"
                        group.addTask {
                            await self.probeAnycubicPrinter(ipAddress: ip)
                        }
                    }
                    
                    for await result in group {
                        if let printer = result {
                            await MainActor.run {
                                self.addDiscoveredPrinter(printer)
                            }
                        }
                    }
                }
                
                scannedCount += (batchEnd - batchStart + 1)
                
                await MainActor.run {
                    self.scanProgress = Double(scannedCount) / Double(totalHosts)
                }
            }
            
            await MainActor.run {
                self.isScanning = false
                self.scanProgress = 1.0
            }
        }
    }
    
    // MARK: - Management
    
    /// Add a discovered printer, avoiding duplicates
    @MainActor
    private func addDiscoveredPrinter(_ printer: DiscoveredPrinter) {
        if !discoveredPrinters.contains(where: { $0.ipAddress == printer.ipAddress }) {
            discoveredPrinters.append(printer)
        }
    }
    
    /// Stop all discovery methods
    func stopDiscovery() {
        browser?.cancel()
        browser = nil
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }
    
    /// Clear discovered printers
    @MainActor
    func clearResults() {
        discoveredPrinters.removeAll()
        lastError = nil
        scanProgress = 0.0
    }
    
    deinit {
        stopDiscovery()
    }
}
