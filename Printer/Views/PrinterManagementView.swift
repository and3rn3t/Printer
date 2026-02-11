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
    
    var body: some View {
        HStack {
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
            
            VStack(alignment: .trailing) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(printer.isConnected ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    
                    Text(printer.isConnected ? "Connected" : "Offline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if let lastConnected = printer.lastConnected {
                    Text("Last: \(lastConnected.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
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
                    .disabled(ipAddress.isEmpty || isTestingConnection)
                    
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
                    .disabled(name.isEmpty || ipAddress.isEmpty)
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
                let api = AnycubicPrinterAPI()
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
        let printer = Printer(
            name: name,
            ipAddress: ipAddress,
            apiKey: apiKey.isEmpty ? nil : apiKey,
            manufacturer: "Anycubic",
            model: model
        )
        
        // Populate discovery data if available
        if let discovered = selectedDiscoveredPrinter {
            printer.serialNumber = discovered.serialNumber
            printer.port = discovered.port
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
        case .manual: return "hand.tap"
        }
    }
}

// MARK: - Printer Detail

struct PrinterDetailView: View {
    @Bindable var printer: Printer
    @State private var printerStatus: PrinterStatus?
    @State private var jobStatus: PrintJobStatus?
    @State private var isLoadingStatus = false
    @State private var statusError: Error?
    @State private var autoRefreshTask: Task<Void, Never>?
    
    var body: some View {
        Form {
            Section("Information") {
                LabeledContent("Name", value: printer.name)
                LabeledContent("IP Address", value: printer.ipAddress)
                LabeledContent("Manufacturer", value: printer.manufacturer)
                if !printer.model.isEmpty {
                    LabeledContent("Model", value: printer.model)
                }
                if let serial = printer.serialNumber {
                    LabeledContent("Serial", value: serial)
                }
                if let firmware = printer.firmwareVersion {
                    LabeledContent("Firmware", value: firmware)
                }
            }
            
            Section("Status") {
                if isLoadingStatus {
                    HStack {
                        ProgressView()
                        Text("Loading status...")
                    }
                } else if let status = printerStatus {
                    LabeledContent("State", value: status.state.text)
                    
                    if let name = status.printerName {
                        LabeledContent("Printer", value: name)
                    }
                    
                    if let temp = status.temperature {
                        if let bed = temp.bed {
                            LabeledContent("Bed Temperature") {
                                Text("\(Int(bed.actual))°C / \(Int(bed.target))°C")
                            }
                        }
                        
                        if let tool = temp.tool0 {
                            LabeledContent("Nozzle Temperature") {
                                Text("\(Int(tool.actual))°C / \(Int(tool.target))°C")
                            }
                        }
                    }
                } else {
                    Button("Refresh Status") {
                        loadStatus()
                    }
                }
                
                if let error = statusError {
                    Text(error.localizedDescription)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            
            // Active print job section
            if let job = jobStatus, job.state != "Operational" {
                Section("Current Print") {
                    if let file = job.job?.file?.name {
                        LabeledContent("File", value: file)
                    }
                    
                    LabeledContent("State", value: job.state)
                    
                    if let progress = job.progress {
                        if let completion = progress.completion {
                            VStack(alignment: .leading, spacing: 4) {
                                ProgressView(value: completion / 100.0)
                                Text("\(Int(completion))% complete")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        if let timeLeft = progress.printTimeLeft {
                            LabeledContent("Time Remaining") {
                                Text(formatDuration(timeLeft))
                            }
                        }
                    }
                    
                    // Print controls
                    HStack(spacing: 16) {
                        Spacer()
                        
                        if job.state == "Printing" {
                            Button {
                                pausePrint()
                            } label: {
                                Label("Pause", systemImage: "pause.circle.fill")
                            }
                        }
                        
                        if job.state == "Paused" || job.state == "Pausing" {
                            Button {
                                resumePrint()
                            } label: {
                                Label("Resume", systemImage: "play.circle.fill")
                            }
                        }
                        
                        Button(role: .destructive) {
                            cancelPrint()
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle.fill")
                        }
                        
                        Spacer()
                    }
                }
            }
            
            if let lastConnected = printer.lastConnected {
                Section {
                    LabeledContent("Last Connected") {
                        Text(lastConnected.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }
        }
        .navigationTitle(printer.name)
        .refreshable {
            await refreshStatus()
        }
        .onAppear {
            loadStatus()
            startAutoRefresh()
        }
        .onDisappear {
            autoRefreshTask?.cancel()
        }
    }
    
    // MARK: - Status Loading
    
    private func loadStatus() {
        isLoadingStatus = true
        statusError = nil
        
        Task {
            await refreshStatus()
        }
    }
    
    private func refreshStatus() async {
        do {
            let api = AnycubicPrinterAPI()
            let status = try await api.getPrinterStatus(
                ipAddress: printer.ipAddress,
                apiKey: printer.apiKey
            )
            
            // Also try to get job status
            let job = try? await api.getJobStatus(
                ipAddress: printer.ipAddress,
                apiKey: printer.apiKey
            )
            
            await MainActor.run {
                printerStatus = status
                jobStatus = job
                printer.isConnected = true
                printer.lastConnected = Date()
                isLoadingStatus = false
            }
        } catch {
            await MainActor.run {
                statusError = error
                printer.isConnected = false
                isLoadingStatus = false
            }
        }
    }
    
    /// Auto-refresh status every 10 seconds while view is visible
    private func startAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                if Task.isCancelled { break }
                await refreshStatus()
            }
        }
    }
    
    // MARK: - Print Controls
    
    private func pausePrint() {
        Task {
            let api = AnycubicPrinterAPI()
            try? await api.pausePrint(ipAddress: printer.ipAddress, apiKey: printer.apiKey)
            await refreshStatus()
        }
    }
    
    private func resumePrint() {
        Task {
            let api = AnycubicPrinterAPI()
            try? await api.resumePrint(ipAddress: printer.ipAddress, apiKey: printer.apiKey)
            await refreshStatus()
        }
    }
    
    private func cancelPrint() {
        Task {
            let api = AnycubicPrinterAPI()
            try? await api.cancelPrint(ipAddress: printer.ipAddress, apiKey: printer.apiKey)
            await refreshStatus()
        }
    }
    
    // MARK: - Helpers
    
    private func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
