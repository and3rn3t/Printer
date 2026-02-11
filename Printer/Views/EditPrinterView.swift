//
//  EditPrinterView.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import SwiftUI
import SwiftData

/// Sheet for editing an existing printer's configuration.
///
/// Allows changing name, IP address, port, protocol, API key, and model.
struct EditPrinterView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var printer: Printer

    @State private var name: String
    @State private var ipAddress: String
    @State private var port: String
    @State private var apiKey: String
    @State private var model: String
    @State private var selectedProtocol: PrinterProtocol
    @State private var resinCostPerMl: String
    @State private var buildPlateX: String
    @State private var buildPlateY: String
    @State private var buildPlateZ: String
    @State private var isTestingConnection = false
    @State private var connectionTestResult: Result<Bool, Error>?

    init(printer: Printer) {
        self.printer = printer
        _name = State(initialValue: printer.name)
        _ipAddress = State(initialValue: printer.ipAddress)
        _port = State(initialValue: String(printer.port))
        _apiKey = State(initialValue: printer.apiKey ?? "")
        _model = State(initialValue: printer.model)
        _selectedProtocol = State(initialValue: printer.printerProtocol)
        _resinCostPerMl = State(initialValue: printer.resinCostPerMl.map { String(format: "%.2f", $0) } ?? "")
        // Init build plate fields from printer or known defaults
        let known = Printer.knownBuildPlate(for: printer.model)
        _buildPlateX = State(initialValue: (printer.buildPlateX ?? known?.0).map { String(format: "%.0f", $0) } ?? "")
        _buildPlateY = State(initialValue: (printer.buildPlateY ?? known?.1).map { String(format: "%.0f", $0) } ?? "")
        _buildPlateZ = State(initialValue: (printer.buildPlateZ ?? known?.2).map { String(format: "%.0f", $0) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
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
                        Label("Enter a valid IPv4 address", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    TextField("Model", text: $model)
                }

                Section("Connection") {
                    Picker("Protocol", selection: $selectedProtocol) {
                        Text("ACT (TCP)").tag(PrinterProtocol.act)
                        Text("OctoPrint (HTTP)").tag(PrinterProtocol.octoprint)
                        Text("Anycubic HTTP").tag(PrinterProtocol.anycubicHTTP)
                    }
                    .onChange(of: selectedProtocol) { _, newValue in
                        // Update default port when protocol changes
                        switch newValue {
                        case .act: port = "6000"
                        case .octoprint: port = "80"
                        case .anycubicHTTP: port = "18910"
                        }
                    }

                    TextField("Port", text: $port)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif

                    if selectedProtocol == .octoprint {
                        TextField("API Key", text: $apiKey)
                    }
                }

                Section {
                    HStack {
                        Text("Resin Cost")
                        Spacer()
                        TextField("0.00", text: $resinCostPerMl)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text("/ mL")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Cost")
                } footer: {
                    Text("Per-printer cost overrides the global setting. Leave blank to use the global resin cost.")
                }

                Section {
                    HStack {
                        Text("Width")
                        Spacer()
                        TextField("198", text: $buildPlateX)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                        Text("mm")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Depth")
                        Spacer()
                        TextField("122", text: $buildPlateY)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                        Text("mm")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Height")
                        Spacer()
                        TextField("245", text: $buildPlateZ)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                        Text("mm")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Build Plate")
                } footer: {
                    Text("Set your printer's build volume for model fit checks.")
                }

                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            if isTestingConnection {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Testing…")
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

                if let serial = printer.serialNumber {
                    Section("Device Info") {
                        LabeledContent("Serial Number", value: serial)
                        if let firmware = printer.firmwareVersion {
                            LabeledContent("Firmware", value: firmware)
                        }
                    }
                }
            }
            .navigationTitle("Edit Printer")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { savePrinter() }
                        .disabled(name.isEmpty || ipAddress.isEmpty || !isValidIPAddress(ipAddress))
                }
            }
        }
    }

    // MARK: - Actions

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

    private func savePrinter() {
        printer.name = name
        printer.ipAddress = ipAddress
        printer.port = Int(port) ?? 6000
        printer.apiKey = apiKey.isEmpty ? nil : apiKey
        printer.model = model
        printer.printerProtocol = selectedProtocol
        printer.resinCostPerMl = Double(resinCostPerMl)
        printer.buildPlateX = Float(buildPlateX)
        printer.buildPlateY = Float(buildPlateY)
        printer.buildPlateZ = Float(buildPlateZ)
        dismiss()
    }
}
