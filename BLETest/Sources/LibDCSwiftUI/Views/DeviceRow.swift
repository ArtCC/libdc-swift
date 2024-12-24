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
        
        guard let deviceName = device.name else {
            logError("Device has no name")
            isConnecting = false
            return
        }
        
        let success = DeviceConfiguration.openBLEDevice(
            name: deviceName,
            deviceAddress: device.identifier.uuidString
        )
        
        if success {
            // Allocate device_data_t on the heap
            let deviceDataPtr = UnsafeMutablePointer<device_data_t>.allocate(capacity: 1)
            deviceDataPtr.initialize(to: device_data_t())
            
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
            logInfo("Successfully opened \(deviceName)")
            showConnectedDeviceSheet = true
        } else {
            logError("Failed to open \(deviceName)")
        }
        
        isConnecting = false
    }
}
