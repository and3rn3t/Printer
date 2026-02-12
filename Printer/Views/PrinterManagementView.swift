//
//  PrinterManagementView.swift
//  Printer
//
//  Created by Matt on 2/10/26.
//

import SwiftUI
import SwiftData

struct PrinterManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var printers: [Printer]
    
    @State private var showingAddPrinter = false
    @State private var networkMonitor = NetworkMonitor()
    
    var body: some View {
        NavigationStack {
            Group {
                if printers.isEmpty {
                    ContentUnavailableView(
                        "No Printers",
                        systemImage: "printer.slash",
                        description: Text("Add your first 3D printer to get started")
                    )
                } else {
                    List {
                        // Network status banner
                        if !networkMonitor.canAccessLocalPrinters {
                            Section {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(networkMonitor.statusDescription)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text("Connect to WiFi to access local printers")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "wifi.exclamationmark")
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        
                        Section {
                            ForEach(printers) { printer in
                                NavigationLink(destination: PrinterDetailView(printer: printer)) {
                                    PrinterRowView(printer: printer)
                                }
                            }
                            .onDelete(perform: deletePrinters)
                        }
                    }
                }
            }
            .navigationTitle("Printers")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddPrinter = true
                    } label: {
                        Label("Add Printer", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddPrinter) {
                AddPrinterView()
            }
        }
    }
    
    private func deletePrinters(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(printers[index])
            }
        }
    }
}

// MARK: - Printer Row

struct PrinterRowView: View {
    @Bindable var printer: Printer
    @State private var liveStatus: PhotonPrinterService.PhotonStatus?
    @State private var isReachable: Bool?
    @State private var checkTask: Task<Void, Never>?

    var body: some View {
        HStack {
            // Status indicator
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 32, height: 32)

                Image(systemName: statusIcon)
                    .font(.system(size: 14))
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(printer.name)
                    .font(.headline)

                Text(printer.ipAddress)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !printer.model.isEmpty {
                    Text("\(printer.manufacturer) \(printer.model)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(connectionDotColor)
                        .frame(width: 8, height: 8)

                    Text(connectionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let status = liveStatus {
                    Text(status.displayText)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(status.color)
                } else if let lastConnected = printer.lastConnected {
                    Text(lastConnected.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            startQuickCheck()
        }
        .onDisappear {
            checkTask?.cancel()
        }
    }

    // MARK: - Quick Connection Check

    private func startQuickCheck() {
        checkTask?.cancel()
        checkTask = Task {
            // Quick probe to update row status
            if printer.printerProtocol == .act {
                let service = PhotonPrinterService.shared
                if let status = try? await service.getStatus(
                    ipAddress: printer.ipAddress,
                    port: printer.port
                ) {
                    await MainActor.run {
                        liveStatus = status
                        isReachable = true
                        printer.isConnected = true
                    }
                } else {
                    await MainActor.run {
                        isReachable = false
                        printer.isConnected = false
                    }
                }
            } else {
                let api = AnycubicPrinterAPI()
                let reachable = await api.isReachable(ipAddress: printer.ipAddress)
                await MainActor.run {
                    isReachable = reachable
                    printer.isConnected = reachable
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var statusColor: Color {
        guard let status = liveStatus else {
            if isReachable == true { return .green }
            if isReachable == false { return .gray }
            return .gray.opacity(0.5)
        }
        return status.color
    }

    private var statusIcon: String {
        guard let status = liveStatus else {
            if isReachable == nil { return "circle.dotted" }
            return isReachable == true ? "checkmark.circle" : "xmark.circle"
        }
        switch status {
        case .idle: return "checkmark.circle"
        case .printing: return "printer.fill"
        case .paused: return "pause.circle"
        case .stopping: return "stop.circle"
        case .unknown: return "questionmark.circle"
        }
    }

    private var connectionDotColor: Color {
        if isReachable == true { return .green }
        if isReachable == false { return .gray }
        return .orange // checking
    }

    private var connectionText: String {
        if isReachable == nil { return "Checking…" }
        return isReachable == true ? "Online" : "Offline"
    }
}

// MARK: - Add Printer

struct AddPrinterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var name = ""
    @State private var ipAddress = ""
    @State private var apiKey = ""
    @State private var model = ""
    
    @State private var isTestingConnection = false
    @State private var connectionTestResult: Result<Bool, Error>?
    
    // Discovery
    @State private var discovery = PrinterDiscovery()
    @State private var showingDiscovery = false
    @State private var selectedDiscoveredPrinter: DiscoveredPrinter?
    
    var body: some View {
        NavigationStack {
            Form {
                // Auto-discovery section
                Section {
                    Button {
                        showingDiscovery = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Find Printers on Network")
                                Text("Auto-discover Anycubic printers")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundStyle(.blue)
                        }
                    }
                    
                    if let selected = selectedDiscoveredPrinter {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading) {
                                Text(selected.name)
                                    .font(.subheadline)
                                Text("\(selected.ipAddress) via \(selected.discoveryMethod.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                Section("Printer Information") {
                    TextField("Name", text: $name)
                    TextField("IP Address", text: $ipAddress)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        .textContentType(.none)
                        #endif
                        .onChange(of: ipAddress) { _, _ in
                            connectionTestResult = nil
                        }
                    
                    if !ipAddress.isEmpty && !isValidIPAddress(ipAddress) {
                        Label("Enter a valid IPv4 address (e.g. 192.168.1.49)", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    
                    TextField("Model (Optional)", text: $model)
                }
                
                Section("Authentication") {
                    TextField("API Key (Optional)", text: $apiKey)
                }
                
                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            if isTestingConnection {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Testing...")
                            } else {
                                Image(systemName: "network")
                                Text("Test Connection")
                            }
                        }
                    }
                    .disabled(ipAddress.isEmpty || !isValidIPAddress(ipAddress) || isTestingConnection)
                    
                    if let result = connectionTestResult {
                        switch result {
                        case .success(let connected):
                            Label(
                                connected ? "Connection successful" : "Connection failed",
                                systemImage: connected ? "checkmark.circle.fill" : "xmark.circle.fill"
                            )
                            .foregroundStyle(connected ? .green : .red)
                            
                        case .failure(let error):
                            Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Add Printer")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addPrinter()
                    }
                    .disabled(name.isEmpty || ipAddress.isEmpty || !isValidIPAddress(ipAddress))
                }
            }
            .sheet(isPresented: $showingDiscovery) {
                PrinterDiscoveryView(discovery: discovery) { printer in
                    selectedDiscoveredPrinter = printer
                    name = printer.name
                    ipAddress = printer.ipAddress
                    model = printer.model
                    showingDiscovery = false
                }
            }
        }
    }
    
    private func testConnection() {
        isTestingConnection = true
        connectionTestResult = nil
        
        Task {
            do {
                let api = AnycubicPrinterAPI.shared
                let connected = try await api.testConnection(ipAddress: ipAddress)
                
                await MainActor.run {
                    connectionTestResult = .success(connected)
                    isTestingConnection = false
                }
            } catch {
                await MainActor.run {
                    connectionTestResult = .failure(error)
                    isTestingConnection = false
                }
            }
        }
    }
    
    private func addPrinter() {
        // Determine protocol based on discovery method
        let printerProtocol: PrinterProtocol
        let port: Int
        if let discovered = selectedDiscoveredPrinter {
            switch discovered.discoveryMethod {
            case .anycubicACT:
                printerProtocol = .act
                port = PhotonPrinterService.defaultPort
            case .anycubicHTTP:
                printerProtocol = .anycubicHTTP
                port = 18910
            default:
                printerProtocol = .octoprint
                port = 80
            }
        } else {
            printerProtocol = .act  // Default to ACT for Anycubic printers
            port = PhotonPrinterService.defaultPort
        }
        
        let printer = Printer(
            name: name,
            ipAddress: ipAddress,
            apiKey: apiKey.isEmpty ? nil : apiKey,
            manufacturer: "Anycubic",
            model: model,
            port: port,
            printerProtocol: printerProtocol
        )
        
        // Populate discovery data if available
        if let discovered = selectedDiscoveredPrinter {
            printer.serialNumber = discovered.serialNumber
        }
        
        modelContext.insert(printer)
        dismiss()
    }
}

// MARK: - Printer Discovery View

struct PrinterDiscoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var discovery: PrinterDiscovery
    let onSelect: (DiscoveredPrinter) -> Void
    
    @State private var subnetIP = ""
    
    var body: some View {
        NavigationStack {
            List {
                // Scan controls
                Section {
                    Button {
                        discovery.startBonjourDiscovery()
                    } label: {
                        Label("Bonjour Scan", systemImage: "bonjour")
                    }
                    .disabled(discovery.isScanning)
                    
                    HStack {
                        TextField("Subnet (e.g. 192.168.1.1)", text: $subnetIP)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        
                        Button {
                            discovery.scanSubnet(baseIP: subnetIP.isEmpty ? nil : subnetIP)
                        } label: {
                            Text("Scan")
                        }
                        .disabled(discovery.isScanning)
                    }
                    
                    if discovery.isScanning {
                        VStack(spacing: 8) {
                            ProgressView(value: discovery.scanProgress)
                            Text("Scanning network... \(Int(discovery.scanProgress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Discovery Methods")
                }
                
                // Results
                Section {
                    if discovery.discoveredPrinters.isEmpty && !discovery.isScanning {
                        ContentUnavailableView(
                            "No Printers Found",
                            systemImage: "printer.slash",
                            description: Text("Start a scan to find printers on your network")
                        )
                    } else {
                        ForEach(discovery.discoveredPrinters) { printer in
                            Button {
                                onSelect(printer)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(printer.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        
                                        Text(printer.ipAddress)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        
                                        HStack(spacing: 4) {
                                            Image(systemName: discoveryIcon(for: printer.discoveryMethod))
                                                .font(.caption2)
                                            Text(printer.discoveryMethod.rawValue)
                                                .font(.caption2)
                                        }
                                        .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if !printer.model.isEmpty {
                                        Text(printer.model)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Found Printers")
                        Spacer()
                        Text("\(discovery.discoveredPrinters.count)")
                            .foregroundStyle(.secondary)
                    }
                }
                
                if let error = discovery.lastError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Find Printers")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        discovery.stopDiscovery()
                        dismiss()
                    }
                }
            }
            .onDisappear {
                discovery.stopDiscovery()
            }
        }
    }
    
    private func discoveryIcon(for method: DiscoveredPrinter.DiscoveryMethod) -> String {
        switch method {
        case .bonjour: return "bonjour"
        case .anycubicHTTP: return "antenna.radiowaves.left.and.right"
        case .anycubicACT: return "network"
        case .manual: return "hand.tap"
        }
    }
}
