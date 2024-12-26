struct DeviceRow: View {
    let device: CBPeripheral
    @ObservedObject var bluetoothManager: CoreBluetoothManager
    @ObservedObject var diveViewModel: DiveDataViewModel
    @Binding var showConnectedDeviceSheet: Bool
    
    private var isConnected: Bool {
        bluetoothManager.connectionState == .ready && 
        bluetoothManager.connectedDevice?.identifier == device.identifier
    }
    
    private var deviceInfo: String? {
        guard let name = device.name,
              let info = DeviceConfiguration.identifyDevice(name: name) else {
            return nil
        }
        return "\(info.family) - Model \(info.model)"
    }
    
    var body: some View {
        Button(action: {
            if isConnected {
                showConnectedDeviceSheet = true
            } else {
                bluetoothManager.connectToPeripheral(device)
            }
        }) {
            HStack {
                VStack(alignment: .leading) {
                    Text(device.name ?? "Unknown Device")
                        .foregroundColor(isConnected ? .blue : .primary)
                    if let info = deviceInfo {
                        Text(info)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
                if isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
        }
    }
} 