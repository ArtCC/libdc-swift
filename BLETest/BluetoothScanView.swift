import SwiftUI
import CoreBluetooth
import Combine

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
            
            // Now, open the Suunto EON Steel device
            let opened = DeviceConfiguration.openSuuntoEonSteel(deviceAddress: device.identifier.uuidString)
            if opened {
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
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Connected to: \(device.name ?? "Unknown Device")")
                    .font(.headline)
                    .padding()
                
                List {
                    Section(header: Text("Received Responses")) {
                        ForEach(receivedResponses, id: \.self) { response in
                            Text(response)
                        }
                    }
                }
                
                HStack {
                    Button("Read Data") {
                        if let data = bluetoothManager.readData(100) {
                            receivedResponses.append("Received data: \(data.count) bytes")
                        } else {
                            receivedResponses.append("Read error")
                        }
                    }
                    
                    Button("Write Data") {
                        let data = "Hello, BLE!".data(using: .utf8)!
                        let success = bluetoothManager.writeData(data)
                        if success {
                            receivedResponses.append("Data written successfully")
                        } else {
                            receivedResponses.append("Write error")
                        }
                    }
                }
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
}