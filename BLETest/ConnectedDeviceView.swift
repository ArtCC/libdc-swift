import SwiftUI
import CoreBluetooth
import Combine
import Foundation

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
                            if let devicePtr = bluetoothManager.openedDeviceDataPtr,
                               devicePtr.pointee.have_progress != 0 {
                                Text("Downloading dive \(devicePtr.pointee.progress.current) of \(devicePtr.pointee.progress.maximum)")
                                    .padding(.leading)
                            } else {
                                Text(diveViewModel.progress.description)
                                    .padding(.leading)
                            }
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
        isRetrievingLogs = true
        diveViewModel.clear()
        diveViewModel.progress = .idle
        
        guard let devicePtr = bluetoothManager.openedDeviceDataPtr,
              let device = devicePtr.pointee.device else {
            diveViewModel.setError("No opened device found.")
            isRetrievingLogs = false
            return
        }
        
        // Create a struct to hold both the response holder and view model
        struct CallbackContext {
            var logCount: Int = 0
            var totalLogs: Int = 0
            let viewModel: DiveDataViewModel
            var lastFingerprint: Data?
        }
        
        var context = CallbackContext(viewModel: diveViewModel)
        
        // Create a callback to handle each dive
        let callback: @convention(c) (
            UnsafePointer<UInt8>?,
            UInt32,
            UnsafePointer<UInt8>?,
            UInt32,
            UnsafeMutableRawPointer?
        ) -> Int32 = { data, size, fingerprint, fsize, userdata in
            guard let data = data,
                  let contextPtr = userdata?.assumingMemoryBound(to: CallbackContext.self),
                  let fingerprint = fingerprint else {
                return 0
            }
            
            // Store fingerprint of the most recent dive
            let fingerprintData = Data(bytes: fingerprint, count: Int(fsize))
            contextPtr.pointee.lastFingerprint = fingerprintData
            
            contextPtr.pointee.logCount += 1
            let currentDiveNumber = contextPtr.pointee.logCount
            
            // Update progress
            DispatchQueue.main.async {
                contextPtr.pointee.viewModel.updateProgress(
                    current: currentDiveNumber,
                    total: nil  // We don't know the total
                )
            }
            
            logInfo("Now parsing dive #\(currentDiveNumber)")
            
            // Create a parser for this dive
            var parser: OpaquePointer?
            let context: OpaquePointer? = nil
            let rc = suunto_eonsteel_parser_create(&parser, context, data, Int(size), 0)
            
            if rc == DC_STATUS_SUCCESS && parser != nil {
                logDebug("Parser created successfully for dive #\(currentDiveNumber)")
                
                // Get dive time
                var datetime = dc_datetime_t()
                if dc_parser_get_datetime(parser, &datetime) == DC_STATUS_SUCCESS {
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
                        logError("Failed to process samples for dive #\(currentDiveNumber)")
                    }
                } else {
                    logError("Failed to get datetime for dive #\(currentDiveNumber)")
                }
                
                dc_parser_destroy(parser)
            } else {
                logError("Failed to create parser for dive #\(currentDiveNumber), status: \(rc)")
            }
            
            return 1
        }
        
        // Run the enumeration in the background to keep the UI responsive
        DispatchQueue.global(qos: .userInitiated).async {
            logInfo("Starting dive enumeration...")
            let status = dc_device_foreach(device, callback, &context)
            
            // Once done, update status & UI on the main thread
            DispatchQueue.main.async {
                if status == DC_STATUS_SUCCESS {
                    if let lastFingerprint = context.lastFingerprint {
                        diveViewModel.saveFingerprint(lastFingerprint)
                    }
                    diveViewModel.progress = .completed
                } else {
                    diveViewModel.setError("Error enumerating dives: \(status)")
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

