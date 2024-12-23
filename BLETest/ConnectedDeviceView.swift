import SwiftUI
import CoreBluetooth
import Combine
import Foundation

struct ConnectedDeviceView: View {
    let device: CBPeripheral
    @ObservedObject var bluetoothManager: CoreBluetoothManager
    @StateObject private var diveViewModel = DiveDataViewModel()
    @Environment(\.presentationMode) var presentationMode
    @State private var isRetrievingLogs = false
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Connected to: \(device.name ?? "Unknown Device")")
                    .font(.headline)
                    .padding()
                
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
                
                if !diveViewModel.status.isEmpty {
                    Text(diveViewModel.status)
                        .foregroundColor(.secondary)
                        .padding()
                }
                
                Button(action: retrieveDiveLogs) {
                    if isRetrievingLogs {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Text("Retrieve Dive Logs")
                    }
                }
                .disabled(isRetrievingLogs)
                .padding()
            }
            .navigationTitle("Connected Device")
            .navigationBarItems(leading: Button {
                presentationMode.wrappedValue.dismiss()
            } label: {
                Image(systemName: "xmark")
            })
            .navigationBarItems(trailing: Button("Disconnect") {
                print("Disconnect button pressed")
                bluetoothManager.close()
                DispatchQueue.main.async {
                    self.bluetoothManager.objectWillChange.send()
                }
                presentationMode.wrappedValue.dismiss()
            })
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func retrieveDiveLogs() {
        isRetrievingLogs = true
        diveViewModel.clear()
        diveViewModel.updateStatus("Starting dive log retrieval...")
        
        guard let deviceData = bluetoothManager.openedDeviceData,
              let device = deviceData.device else {
            diveViewModel.updateStatus("No opened device found.")
            isRetrievingLogs = false
            return
        }
        
        // Create a struct to hold both the response holder and view model
        struct CallbackContext {
            var logCount: Int = 0
            let viewModel: DiveDataViewModel
        }
        
        var context = CallbackContext(viewModel: diveViewModel)
        
        // Create a callback to handle each dive
        let callback: @convention(c) (
            UnsafePointer<UInt8>?,
            UInt32,
            UnsafePointer<UInt8>?,
            UInt32,
            UnsafeMutableRawPointer?
        ) -> Int32 = { data, size, _, _, userdata in
            guard let data = data,
                  let contextPtr = userdata?.assumingMemoryBound(to: CallbackContext.self) else {
                return 0
            }
            
            // Stop after retrieving 2 logs
            if contextPtr.pointee.logCount >= 2 {
                return 0  // Tells libdivecomputer to skip remaining logs
            }
            contextPtr.pointee.logCount += 1
            let currentDiveNumber = contextPtr.pointee.logCount
            
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
                        // Update the view model with the new dive
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
            
            return 1 // Continue enumeration
        }
        
        logInfo("Starting dive enumeration...")
        let status = dc_device_foreach(
            device,
            callback,
            &context
        )
        
        // Update final status
        if status == DC_STATUS_SUCCESS {
            diveViewModel.updateStatus("Successfully enumerated \(context.logCount) dives")
        } else {
            diveViewModel.updateStatus("Error enumerating dives: \(status)")
            logError("Failed to enumerate dives, status: \(status)")
        }
        
        isRetrievingLogs = false
    }
}

