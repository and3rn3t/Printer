//
//  NetworkMonitor.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import Foundation
import Network
import Observation

/// Monitors network connectivity and provides status updates
///
/// Uses NWPathMonitor to observe network path changes and track
/// whether the device is connected to a local network (WiFi/Ethernet).
@Observable
final class NetworkMonitor {
    
    // MARK: - Properties
    
    /// Whether the device has any network connection
    private(set) var isConnected: Bool = false
    
    /// Whether the device is on a local network (WiFi or wired)
    private(set) var isOnLocalNetwork: Bool = false
    
    /// Current network interface type
    private(set) var interfaceType: InterfaceType = .unknown
    
    /// Human-readable network status description
    var statusDescription: String {
        if !isConnected {
            return "No Network"
        }
        switch interfaceType {
        case .wifi:
            return "WiFi Connected"
        case .wiredEthernet:
            return "Ethernet Connected"
        case .cellular:
            return "Cellular (Local printers unavailable)"
        case .unknown:
            return "Connected"
        }
    }
    
    /// Whether the current network supports local printer access
    var canAccessLocalPrinters: Bool {
        isConnected && isOnLocalNetwork
    }
    
    enum InterfaceType {
        case wifi
        case wiredEthernet
        case cellular
        case unknown
    }
    
    // MARK: - Private
    
    private let monitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "com.printer.networkMonitor", qos: .utility)
    
    // MARK: - Initialization
    
    init() {
        monitor = NWPathMonitor()
        startMonitoring()
    }
    
    deinit {
        monitor.cancel()
    }
    
    // MARK: - Monitoring
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.updateStatus(with: path)
            }
        }
        monitor.start(queue: monitorQueue)
    }
    
    @MainActor
    private func updateStatus(with path: NWPath) {
        isConnected = path.status == .satisfied
        
        // Determine interface type
        if path.usesInterfaceType(.wifi) {
            interfaceType = .wifi
            isOnLocalNetwork = true
        } else if path.usesInterfaceType(.wiredEthernet) {
            interfaceType = .wiredEthernet
            isOnLocalNetwork = true
        } else if path.usesInterfaceType(.cellular) {
            interfaceType = .cellular
            isOnLocalNetwork = false
        } else {
            interfaceType = .unknown
            isOnLocalNetwork = isConnected
        }
    }
}
