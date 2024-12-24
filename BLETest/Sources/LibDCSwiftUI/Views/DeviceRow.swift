//
//  DeviceRow.swift
//  BLETest
//
//  Created by User on 24/12/2024.
//

import Foundation
import SwiftUI
import CoreBluetooth

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
                    connectToDevice()
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
    
    private func connectToDevice() {
        logInfo("Initiating connect for \(device.name ?? "Unknown Device")")
        
        let deviceAddress = device.identifier.uuidString
        
        // Attempt to identify and open the device
        if DeviceConfiguration.openBLEDevice(name: device.name ?? "", deviceAddress: deviceAddress) {
            logInfo("Successfully opened \(device.name ?? "Unknown Device")")
            
            // Verify device data pointer is set
            if bluetoothManager.openedDeviceDataPtr == nil {
                logError("Device opened but device data pointer is nil")
                return
            }
            
            showConnectedDeviceSheet = true
        } else {
            logError("Failed to open device")
        }
    }
}
