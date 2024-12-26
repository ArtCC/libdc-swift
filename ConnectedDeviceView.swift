struct ConnectedDeviceView: View {
    // ... existing properties ...
    @State private var isDeviceReady = false
    
    // Add this computed property to access device identity
    private var deviceIdentity: (name: String, family: DeviceConfiguration.DeviceFamily, model: Int)? {
        bluetoothManager.getCurrentDeviceInfo()
    }
    
    // Update modelInfo to use deviceIdentity
    private var modelInfo: (name: String, number: String) {
        guard let identity = deviceIdentity else {
            return (name: "Unknown", number: "N/A")
        }
        
        let modelName = getModelName(family: identity.family, model: UInt32(identity.model))
        return (name: modelName, number: String(identity.model))
    }
    
    // Update deviceDetails
    private var deviceDetails: (modelName: String, firmware: String, serial: String) {
        // First try to get live device info
        if let devicePtr = bluetoothManager.openedDeviceDataPtr,
           devicePtr.pointee.have_devinfo != 0 {
            let info = devicePtr.pointee.devinfo
            return (
                modelName: modelInfo.name,
                firmware: String(format: "%d", info.firmware),
                serial: String(format: "%d", info.serial)
            )
        }
        
        // Fall back to stored identity
        return (
            modelName: modelInfo.name,
            firmware: "N/A",
            serial: "N/A"
        )
    }
    
    private func ensureDeviceSetup() {
        logInfo("ConnectedDeviceView appeared for device: \(device.name ?? "Unknown")")
        
        // Check device pointer status
        if let devicePtr = bluetoothManager.openedDeviceDataPtr {
            logInfo("Device pointer exists - has_device: \(devicePtr.pointee.device != nil), has_context: \(devicePtr.pointee.context != nil)")
            if devicePtr.pointee.device != nil {
                logInfo("Device is properly initialized")
                isDeviceReady = true
                updateDeviceInfo()
                return
            } else {
                logWarning("Device pointer exists but device is not initialized")
            }
        } else {
            logInfo("No device pointer exists, attempting setup")
        }
        
        // If device is already connected, try setup
        if device.state == .connected {
            logInfo("Device is connected, attempting setup")
            bluetoothManager.connectToPeripheral(device)
        } else {
            logInfo("Device not connected, attempting reconnect")
            bluetoothManager.reconnectToSavedDevice()
        }
    }
    
    private func updateDeviceInfo() {
        logInfo("Updating device info...")
        guard let devicePtr = bluetoothManager.openedDeviceDataPtr else {
            logError("Device pointer is nil during updateDeviceInfo")
            return
        }
        
        if devicePtr.pointee.have_devinfo != 0 {
            let info = devicePtr.pointee.devinfo
            deviceInfo = String(format: "Model: %d\nFirmware: %d\nSerial: %d",
                              info.model, info.firmware, info.serial)
            logInfo("Device info updated successfully")
        } else {
            logInfo("Device info not available yet")
        }
    }
    
    private func retrieveDiveLogs() {
        logInfo("🎯 Starting dive log retrieval for device: \(device.name ?? "Unknown")")
        
        guard let devicePtr = bluetoothManager.openedDeviceDataPtr else {
            logError("❌ Device data pointer is nil during retrieveDiveLogs")
            errorMessage = "No device connection found"
            showError = true
            return
        }
        
        logInfo("Device pointer check - has_device: \(devicePtr.pointee.device != nil), has_context: \(devicePtr.pointee.context != nil)")
        guard devicePtr.pointee.device != nil else {
            logError("❌ Device is not properly initialized")
            errorMessage = "Device not properly initialized"
            showError = true
            return
        }
        
        isRetrievingLogs = true
        // ... rest of the retrieval code ...
    }
    
    var body: some View {
        List {
            // ... existing sections ...
            
            if !isDeviceReady {
                Section {
                    HStack {
                        ProgressView()
                        Text("Connecting to device...")
                            .foregroundColor(.gray)
                    }
                }
            }
            
            // ... rest of the view ...
        }
        .navigationTitle("Connected Device")
        .navigationBarItems(trailing: Button(action: {
            bluetoothManager.close()
            DispatchQueue.main.async {
                self.bluetoothManager.objectWillChange.send()
            }
            presentationMode.wrappedValue.dismiss()
        }) {
            Image(systemName: "pause.circle")
        })
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            ensureDeviceSetup()
        }
        .onDisappear {
            if isRetrievingLogs {
                isRetrievingLogs = false
            }
        }
    }
} 