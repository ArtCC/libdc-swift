//
//  ConnectedDeviceView.swift
//  BLETest
//
//  Created by User on 24/12/2024.
//

import SwiftUI
import CoreBluetooth
import Combine
import Foundation

private struct CallbackContext {
    var logCount: Int = 0
    var totalLogs: Int = 0
    let viewModel: DiveDataViewModel
    var lastFingerprint: Data?
    let deviceName: String
}

private func diveCallback(
    data: UnsafePointer<UInt8>?,
    size: UInt32,
    fingerprint: UnsafePointer<UInt8>?,
    fsize: UInt32,
    userdata: UnsafeMutableRawPointer?
) -> Int32 {
    guard let data = data,
          let contextPtr = userdata?.assumingMemoryBound(to: CallbackContext.self),
          let fingerprint = fingerprint else {
        logError("❌ diveCallback: Required parameters are nil")
        return 0
    }
    
    // Store fingerprint of the most recent dive
    let fingerprintData = Data(bytes: fingerprint, count: Int(fsize))
    contextPtr.pointee.lastFingerprint = fingerprintData
    
    // Increment counter before using it
    contextPtr.pointee.logCount += 1
    let currentDiveNumber = contextPtr.pointee.logCount
    logInfo("📊 Processing dive #\(currentDiveNumber)")
    
    // Update progress with the current dive number
    DispatchQueue.main.async {
        contextPtr.pointee.viewModel.updateProgress(
            current: currentDiveNumber,
            total: nil
        )
    }

    // Create a parser for this dive based on device family
    var parser: OpaquePointer?
    let context: OpaquePointer? = nil
    
    // Get device family and model
    if let deviceInfo = DeviceConfiguration.identifyDevice(name: contextPtr.pointee.deviceName) {
        let rc: dc_status_t
        
        switch deviceInfo.family {
        case .suuntoEonSteel:
            rc = suunto_eonsteel_parser_create(&parser, context, data, Int(size), 0)
        case .shearwaterPetrel:
            rc = shearwater_petrel_parser_create(&parser, context, data, Int(size))
        case .shearwaterPredator:
            rc = shearwater_predator_parser_create(&parser, context, data, Int(size))
        }
        
        if rc == DC_STATUS_SUCCESS && parser != nil {
            // Get dive time
            var datetime = dc_datetime_t()
            let datetimeStatus = dc_parser_get_datetime(parser, &datetime)
            
            if datetimeStatus == DC_STATUS_SUCCESS {
                // Create sample data holder
                struct SampleData {
                    var maxDepth: Double = 0.0
                    var lastTemperature: Double = 0.0
                }
                var sampleData = SampleData()
                
                // Create sample callback
                let sampleCallback: dc_sample_callback_t = { type, valuePtr, userData in
                    guard let sampleDataPtr = userData?.assumingMemoryBound(to: SampleData.self),
                          let value = valuePtr?.pointee else {
                        logError("❌ Sample callback: Required parameters are nil")
                        return
                    }
                    
                    switch type {
                    case DC_SAMPLE_DEPTH:
                        if value.depth > sampleDataPtr.pointee.maxDepth {
                            sampleDataPtr.pointee.maxDepth = value.depth
                        }
                    case DC_SAMPLE_TEMPERATURE:
                        sampleDataPtr.pointee.lastTemperature = value.temperature
                    default:
                        break
                    }
                }
                
                // Process all samples
                let samplesStatus = dc_parser_samples_foreach(parser, sampleCallback, &sampleData)
                
                if samplesStatus == DC_STATUS_SUCCESS {
                    DispatchQueue.main.async {
                        contextPtr.pointee.viewModel.addDive(
                            number: currentDiveNumber,
                            year: Int(datetime.year),
                            month: Int(datetime.month),
                            day: Int(datetime.day),
                            hour: Int(datetime.hour),
                            minute: Int(datetime.minute),
                            second: Int(datetime.second),
                            maxDepth: sampleData.maxDepth,
                            temperature: sampleData.lastTemperature
                        )
                    }
                } else {
                    logError("❌ Failed to process samples for dive #\(currentDiveNumber)")
                }
            } else {
                logError("❌ Failed to get datetime for dive #\(currentDiveNumber)")
            }
            
            dc_parser_destroy(parser)
        } else {
            logError("❌ Failed to create parser for dive #\(currentDiveNumber), status: \(rc)")
        }
    } else {
        logError("❌ Failed to identify device family for \(contextPtr.pointee.deviceName)")
    }
    
    return 1
}

struct ConnectedDeviceView: View {
    let device: CBPeripheral
    @ObservedObject var bluetoothManager: CoreBluetoothManager
    @ObservedObject var diveViewModel: DiveDataViewModel
    @Environment(\.presentationMode) var presentationMode
    @State private var isRetrievingLogs = false
    @State private var deviceInfo: String = ""
    
    var body: some View {
        VStack {
            Text("Connected to: \(device.name ?? "Unknown Device")")
                .font(.headline)
                .padding()
            
            if !deviceInfo.isEmpty {
                Text(deviceInfo)
                    .font(.subheadline)
                    .padding()
            }
            
            List {
                Section(header: Text("Dive Logs")) {
                    ForEach(diveViewModel.dives) { dive in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Dive #\(dive.number)")
                                .font(.headline)
                            Text(dive.formattedDateTime)
                                .font(.subheadline)
                            HStack {
                                Text(String(format: "%.1fm", dive.maxDepth))
                                Spacer()
                                Text(String(format: "%.1f°C", dive.temperature))
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            
            VStack(spacing: 12) {
                Button(action: retrieveDiveLogs) {
                    if isRetrievingLogs {
                        HStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                            Text(diveViewModel.progress.description)
                                    .padding(.leading)
                        }
                    } else {
                        Text("Retrieve Dive Logs")
                    }
                }
                .disabled(isRetrievingLogs)
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(10)
                .shadow(radius: 2)
            }
            .padding(.bottom)
        }
        .navigationTitle("Connected Device")
        .navigationBarItems(trailing: Button("Disconnect") {
            print("Disconnect button pressed")
            bluetoothManager.close()
            DispatchQueue.main.async {
                self.bluetoothManager.objectWillChange.send()
            }
            presentationMode.wrappedValue.dismiss()
        })
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            updateDeviceInfo()
        }
    }
    
    private func updateDeviceInfo() {
        guard let devicePtr = bluetoothManager.openedDeviceDataPtr,
              devicePtr.pointee.have_devinfo != 0 else {
            return
        }
        
        let info = devicePtr.pointee.devinfo
        deviceInfo = String(format: "Model: %d\nFirmware: %d\nSerial: %d",
                          info.model, info.firmware, info.serial)
    }
    
    private func retrieveDiveLogs() {
        logInfo("🎯 Starting dive log retrieval")
        isRetrievingLogs = true
        diveViewModel.clear()
        diveViewModel.progress = .idle
        
        guard let devicePtr = bluetoothManager.openedDeviceDataPtr else {
            logError("❌ Device data pointer is nil")
            diveViewModel.setError("No device data pointer found.")
            isRetrievingLogs = false
            return
        }
        
        guard let device = devicePtr.pointee.device else {
            logError("❌ Device pointer is nil in device data")
            diveViewModel.setError("No opened device found.")
            isRetrievingLogs = false
            return
        }
        
        // Initialize context with device name
        var context = CallbackContext(
            viewModel: diveViewModel,
            deviceName: self.device.name ?? "Unknown Device"
        )
        
        // Run the enumeration in the background to keep the UI responsive
        DispatchQueue.global(qos: .userInitiated).async {
            logInfo("🔄 Starting dive enumeration...")
            let status = dc_device_foreach(device, diveCallback, &context)
            
            // Once done, update status & UI on the main thread
            DispatchQueue.main.async {
                if status == DC_STATUS_SUCCESS {
                    if let lastFingerprint = context.lastFingerprint {
                        logInfo("💾 Saving fingerprint")
                        diveViewModel.saveFingerprint(lastFingerprint)
                    }
                    diveViewModel.progress = .completed
                    logInfo("✅ Dive enumeration completed successfully")
                } else {
                    let errorMsg = "Error enumerating dives: \(status)"
                    logError("❌ \(errorMsg)")
                    diveViewModel.setError(errorMsg)
                }
                isRetrievingLogs = false
            }
        }
        
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if let devicePtr = bluetoothManager.openedDeviceDataPtr,
               devicePtr.pointee.have_progress != 0 {
                DispatchQueue.main.async {
                    diveViewModel.updateProgress(
                        current: Int(devicePtr.pointee.progress.current),
                        total: Int(devicePtr.pointee.progress.maximum)
                    )
                }
            }
            
            if !isRetrievingLogs {
                timer.invalidate()
            }
        }
    }
}
