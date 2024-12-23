import SwiftUI
import CoreBluetooth
import Combine
import Foundation

struct BluetoothScanView: View {
    @StateObject private var bluetoothManager = CoreBluetoothManager.shared
    @StateObject private var diveViewModel = DiveDataViewModel()
    @State private var showingConnectedDeviceSheet = false
    @State private var isLoading = false
    @State private var discoveredPeripherals: [CBPeripheral] = []

    var filteredPeripherals: [CBPeripheral] {
        discoveredPeripherals.filter { $0.name != nil && $0.name != "Unknown Device" }
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("My Devices")) {
                    if let connectedDevice = bluetoothManager.connectedDevice {
                        DeviceRow(device: connectedDevice, 
                                bluetoothManager: bluetoothManager,
                                diveViewModel: diveViewModel,
                                showConnectedDeviceSheet: $showingConnectedDeviceSheet)
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
                            DeviceRow(device: device, 
                                    bluetoothManager: bluetoothManager,
                                    diveViewModel: diveViewModel,
                                    showConnectedDeviceSheet: $showingConnectedDeviceSheet)
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
            .navigationDestination(isPresented: $showingConnectedDeviceSheet) {
                if let connectedDevice = bluetoothManager.connectedDevice {
                    ConnectedDeviceView(device: connectedDevice, 
                                      bluetoothManager: bluetoothManager,
                                      diveViewModel: diveViewModel)
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
    @ObservedObject var diveViewModel: DiveDataViewModel
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
                    logInfo("Initiating disconnect for \(device.name ?? "unknown device")")
                    bluetoothManager.close()
                    showConnectedDeviceSheet = false
                } else {
                    logInfo("Initiating connect for \(device.name ?? "unknown device")")
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
        
        // Only proceed with device setup after successful connection
        if success {
            // Allocate device_data_t on the heap
            let deviceDataPtr = UnsafeMutablePointer<device_data_t>.allocate(capacity: 1)
            deviceDataPtr.initialize(to: device_data_t())
            
            let status = open_suunto_eonsteel(deviceDataPtr, device.identifier.uuidString)
            
            if status == DC_STATUS_SUCCESS {
                // Set the fingerprint if we have one
                if let fingerprint = diveViewModel.lastFingerprint {
                    fingerprint.withUnsafeBytes { buffer in
                        let status = dc_device_set_fingerprint(
                            deviceDataPtr.pointee.device,
                            buffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                            UInt32(buffer.count)
                        )
                        if status != DC_STATUS_SUCCESS {
                            logError("Failed to set fingerprint")
                        }
                    }
                }
                
                bluetoothManager.openedDeviceDataPtr = deviceDataPtr
                logInfo("Successfully opened Suunto EON Steel device")
                showConnectedDeviceSheet = true
            } else {
                logError("Failed to open Suunto EON Steel device")
                deviceDataPtr.deallocate()
            }
        } else {
            logError("Connection failed for \(device.name ?? "the device")")
        }
        isConnecting = false
    }
}
