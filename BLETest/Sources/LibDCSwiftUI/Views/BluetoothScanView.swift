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
