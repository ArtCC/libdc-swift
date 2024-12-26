import Foundation

public class DiveLogRetriever {
    private struct CallbackContext {
        var logCount: Int = 0
        var totalLogs: Int = 0
        let viewModel: DiveDataViewModel
        var lastFingerprint: Data?
        let deviceName: String
    }

    private func diveCallback(
        data: UnsafePointer<UInt8>?,
        size: UInt32,
        fingerprint: UnsafePointer<UInt8>?,
        fsize: UInt32,
        userdata: UnsafeMutableRawPointer?
    ) -> Int32 {
        guard let data = data,
            let contextPtr = userdata?.assumingMemoryBound(to: CallbackContext.self),
            let fingerprint = fingerprint else {
            logError("❌ diveCallback: Required parameters are nil")
            return 0
        }
        
        // Store fingerprint of the most recent dive
        let fingerprintData = Data(bytes: fingerprint, count: Int(fsize))
        contextPtr.pointee.lastFingerprint = fingerprintData
        
        // Increment counter before using it
        contextPtr.pointee.logCount += 1
        let currentDiveNumber = contextPtr.pointee.logCount
        logInfo("📊 Processing dive #\(currentDiveNumber)")
        
        // Update progress with the current dive number
        DispatchQueue.main.async {
            contextPtr.pointee.viewModel.updateProgress(
                current: currentDiveNumber,
                total: nil
            )
        }
        
        // Get device family and model
        if let deviceInfo = DeviceConfiguration.identifyDevice(name: contextPtr.pointee.deviceName) {
            do {
                let diveData = try GenericParser.parseDiveData(
                    family: deviceInfo.family,
                    model: deviceInfo.model,
                    diveNumber: currentDiveNumber,
                    diveData: data,
                    dataSize: Int(size)
                )
                
                DispatchQueue.main.async {
                    contextPtr.pointee.viewModel.dives.append(diveData)
                }
            } catch {
                logError("❌ Failed to parse dive #\(currentDiveNumber): \(error)")
                return 0 // Return 0 on parsing error
            }
        } else {
            logError("❌ Failed to identify device family for \(contextPtr.pointee.deviceName)")
            return 0 // Return 0 if device family identification fails
        }
        
        return 1 // Return 1 on successful processing
    }
    
    public static func retrieveDiveLogs(
        from devicePtr: UnsafeMutablePointer<device_data_t>,
        deviceName: String,
        viewModel: DiveDataViewModel,
        onProgress: ((Int, Int) -> Void)? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        viewModel.clear()
        viewModel.progress = .idle
        
        guard let device = devicePtr.pointee.device else {
            viewModel.setError("No opened device found.")
            completion(false)
            return
        }
        
        // Set the stored fingerprint if we have one
        if let storedFingerprint = viewModel.lastFingerprint {
            let status = dc_device_set_fingerprint(
                device,
                Array(storedFingerprint), // Convert Data to [UInt8]
                UInt32(storedFingerprint.count)
            )
            
            if status != DC_STATUS_SUCCESS {
                logWarning("⚠️ Failed to set fingerprint, will download all dives")
            } else {
                logInfo("✅ Set fingerprint, will only download new dives")
            }
        }
        
        var context = CallbackContext(
            viewModel: viewModel,
            deviceName: deviceName
        )
        
        DispatchQueue.global(qos: .userInitiated).async {
            logInfo("🔄 Starting dive enumeration...")
            let status = dc_device_foreach(device, diveCallback, &context)
            
            DispatchQueue.main.async {
                if status == DC_STATUS_SUCCESS {
                    if let lastFingerprint = context.lastFingerprint {
                        viewModel.saveFingerprint(lastFingerprint)
                    }
                    viewModel.progress = .completed
                    completion(true)
                } else {
                    let errorMsg = "Error enumerating dives: \(status)"
                    viewModel.setError(errorMsg)
                    completion(false)
                }
            }
        }
        
        // Add timer in the retriever
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if devicePtr.pointee.have_progress != 0 {
                onProgress?(
                    Int(devicePtr.pointee.progress.current),
                    Int(devicePtr.pointee.progress.maximum)
                )
            }
            
            if viewModel.progress == .completed || viewModel.progress.description.contains("Error") {
                timer.invalidate()
            }
        }
    }
} 