import SwiftUI
import CoreBluetooth
import Combine
import Foundation

struct BluetoothScanView: View {
    @StateObject private var bluetoothManager = CoreBluetoothManager.shared
    @State private var showingConnectedDeviceSheet = false
    @State private var isLoading = false
    @State private var discoveredPeripherals: [CBPeripheral] = []

    var filteredPeripherals: [CBPeripheral] {
        discoveredPeripherals.filter { $0.name != nil && $0.name != "Unknown Device" }
    }
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("My Devices")) {
                    if let connectedDevice = bluetoothManager.connectedDevice {
                        DeviceRow(device: connectedDevice, bluetoothManager: bluetoothManager, showConnectedDeviceSheet: $showingConnectedDeviceSheet)
                    }
                }
                
                Section(header:
                    HStack {
                        Text("Available Devices")
                        if isLoading {
                            ProgressView()
                        }
                    }
                ) {
                    ForEach(filteredPeripherals, id: \.identifier) { device in
                        if device != bluetoothManager.connectedDevice {
                            DeviceRow(device: device, bluetoothManager: bluetoothManager, showConnectedDeviceSheet: $showingConnectedDeviceSheet)
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Bluetooth Devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        if bluetoothManager.isScanning {
                            bluetoothManager.stopScanning()
                            isLoading = false
                        } else {
                            startScanning()
                        }
                    }) {
                        Image(systemName: bluetoothManager.isScanning ? "stop.circle" : "arrow.triangle.2.circlepath")
                    }
                }
            }
            .fullScreenCover(isPresented: $showingConnectedDeviceSheet) {
                if let connectedDevice = bluetoothManager.connectedDevice {
                    ConnectedDeviceView(device: connectedDevice, bluetoothManager: bluetoothManager)
                }
            }
        }
        .onReceive(bluetoothManager.$discoveredPeripherals) { newPeripherals in
            self.discoveredPeripherals = newPeripherals
        }
    }
    
    private func startScanning() {
        discoveredPeripherals.removeAll()
        bluetoothManager.startScanning()
        isLoading = true
        
        // Stop loading after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            self.isLoading = false
            self.bluetoothManager.stopScanning()
        }
    }
}

struct DeviceRow: View {
    let device: CBPeripheral
    @ObservedObject var bluetoothManager: CoreBluetoothManager
    @Binding var showConnectedDeviceSheet: Bool
    @State private var isConnecting = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(device.name ?? "Unknown Device")
                    .font(.headline)
                Text(device.identifier.uuidString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: {
                if bluetoothManager.connectedDevice?.identifier == device.identifier {
                    print("Initiating disconnect for \(device.name ?? "unknown device")")
                    bluetoothManager.close()
                    showConnectedDeviceSheet = false
                } else {
                    print("Initiating connect for \(device.name ?? "unknown device")")
                    connectToDevice(device)
                }
            }) {
                if isConnecting {
                    ProgressView()
                } else {
                    Text(bluetoothManager.connectedDevice?.identifier == device.identifier ? "Disconnect" : "Connect")
                }
            }
            .disabled(isConnecting)
            .buttonStyle(BorderlessButtonStyle())
        }
    }
    
    private func connectToDevice(_ device: CBPeripheral) {
        isConnecting = true
        let success = bluetoothManager.connectToDevice(device.identifier.uuidString)
        if success {
            print("Connected successfully to \(device.name ?? "the device")")
            
            // Create device_data_t and open the Suunto device
            var deviceData = device_data_t()
            let status = open_suunto_eonsteel(&deviceData, device.identifier.uuidString)
            
            if status == DC_STATUS_SUCCESS {
                // Store the opened device data in the manager
                bluetoothManager.openedDeviceData = deviceData
                print("Successfully opened Suunto EON Steel device")
                showConnectedDeviceSheet = true
            } else {
                print("Failed to open Suunto EON Steel device")
            }
        } else {
            print("Connection failed for \(device.name ?? "the device")")
        }
        isConnecting = false
    }
}

struct ConnectedDeviceView: View {
    let device: CBPeripheral
    @ObservedObject var bluetoothManager: CoreBluetoothManager
    @Environment(\.presentationMode) var presentationMode
    @State private var receivedResponses: [String] = []
    @State private var isRetrievingLogs = false
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Connected to: \(device.name ?? "Unknown Device")")
                    .font(.headline)
                    .padding()
                
                List {
                    Section(header: Text("Dive Logs")) {
                        ForEach(receivedResponses, id: \.self) { response in
                            Text(response)
                        }
                    }
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
        receivedResponses.append("Starting dive log retrieval...")
        
        guard let deviceData = bluetoothManager.openedDeviceData,
              let device = deviceData.device else {
            receivedResponses.append("No opened device found.")
            isRetrievingLogs = false
            return
        }
        
        // Create a class to hold our responses that can be captured by the callback
        class ResponseHolder {
            var responses: [String] = []
            var logCount: Int = 0
        }
        var responseHolder = ResponseHolder()
        
        // Create a callback to handle each dive
        let callback: @convention(c) (
            UnsafePointer<UInt8>?,
            UInt32,
            UnsafePointer<UInt8>?,
            UInt32,
            UnsafeMutableRawPointer?
        ) -> Int32 = { data, size, _, _, userdata in
            guard let data = data else { return 0 }
            
            // Convert the user data pointer to our ResponseHolder
            guard let holderPtr = userdata?.assumingMemoryBound(to: ResponseHolder.self),
                  let holder = holderPtr.pointee as ResponseHolder? else {
                return 0
            }

            // Stop after retrieving 3 logs
            if holder.logCount >= 3 {
                return 0  // Tells libdivecomputer to skip remaining logs
            }
            holder.logCount += 1

            // Create a parser for this dive
            var parser: OpaquePointer?
            let context: OpaquePointer? = nil
            let rc = suunto_eonsteel_parser_create(&parser, context, data, Int(size), 0)
            
            if rc == DC_STATUS_SUCCESS && parser != nil {
                // Get dive time
                var datetime = dc_datetime_t()
                if dc_parser_get_datetime(parser, &datetime) == DC_STATUS_SUCCESS {
                    let response = String(format: "Dive: %04d-%02d-%02d %02d:%02d:%02d",
                                       datetime.year, datetime.month, datetime.day,
                                       datetime.hour, datetime.minute, datetime.second)
                    
                    if let holder = userdata?.assumingMemoryBound(to: ResponseHolder.self).pointee {
                        DispatchQueue.main.async {
                            holder.responses.append(response)
                        }
                    }
                }
                
                // Free the parser
                dc_parser_destroy(parser)
            }
            
            return 1 // Continue enumeration
        }
        
        // Call dc_device_foreach with our callback
        let status = dc_device_foreach(
            device,
            callback,
            &responseHolder
        )
        
        if status == DC_STATUS_SUCCESS {
            // Update our UI with the collected responses
            receivedResponses.append(contentsOf: responseHolder.responses)
            receivedResponses.append("Successfully enumerated all dives")
        } else {
            receivedResponses.append("Error enumerating dives: \(status)")
        }
        
        isRetrievingLogs = false
    }
}
