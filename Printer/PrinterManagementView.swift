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
                        ForEach(printers) { printer in
                            NavigationLink(destination: PrinterDetailView(printer: printer)) {
                                PrinterRowView(printer: printer)
                            }
                        }
                        .onDelete(perform: deletePrinters)
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
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Printer Information") {
                    TextField("Name", text: $name)
                    TextField("IP Address", text: $ipAddress)
                        .keyboardType(.decimalPad)
                        .textContentType(.none)
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
            .navigationBarTitleDisplayMode(.inline)
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
        
        modelContext.insert(printer)
        dismiss()
    }
}

// MARK: - Printer Detail

struct PrinterDetailView: View {
    @Bindable var printer: Printer
    @State private var printerStatus: PrinterStatus?
    @State private var isLoadingStatus = false
    @State private var statusError: Error?
    
    var body: some View {
        Form {
            Section("Information") {
                LabeledContent("Name", value: printer.name)
                LabeledContent("IP Address", value: printer.ipAddress)
                LabeledContent("Manufacturer", value: printer.manufacturer)
                if !printer.model.isEmpty {
                    LabeledContent("Model", value: printer.model)
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
            
            if let lastConnected = printer.lastConnected {
                Section {
                    LabeledContent("Last Connected") {
                        Text(lastConnected.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }
        }
        .navigationTitle(printer.name)
        .onAppear {
            loadStatus()
        }
    }
    
    private func loadStatus() {
        isLoadingStatus = true
        statusError = nil
        
        Task {
            do {
                let api = AnycubicPrinterAPI()
                let status = try await api.getPrinterStatus(
                    ipAddress: printer.ipAddress,
                    apiKey: printer.apiKey
                )
                
                await MainActor.run {
                    printerStatus = status
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
    }
}
