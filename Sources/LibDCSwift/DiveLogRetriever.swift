import Foundation

public class DiveLogRetriever {
    private class CallbackContext {
        var logCount: Int = 0
        var totalLogs: Int = 0
        let viewModel: DiveDataViewModel
        var lastFingerprint: Data?
        let deviceName: String
        
        init(viewModel: DiveDataViewModel, deviceName: String) {
            self.viewModel = viewModel
            self.deviceName = deviceName
        }
    }

    private static let diveCallbackClosure: @convention(c) (
        UnsafePointer<UInt8>?,
        UInt32,
        UnsafePointer<UInt8>?,
        UInt32,
        UnsafeMutableRawPointer?
    ) -> Int32 = { data, size, fingerprint, fsize, userdata in
        guard let data = data,
              let userdata = userdata,
              let fingerprint = fingerprint else {
            logError("❌ diveCallback: Required parameters are nil")
            return 0
        }
        
        // Convert back from UnsafeMutableRawPointer to CallbackContext
        let context = Unmanaged<CallbackContext>.fromOpaque(userdata).takeUnretainedValue()
        
        // Store fingerprint of the most recent dive
        let fingerprintData = Data(bytes: fingerprint, count: Int(fsize))
        context.lastFingerprint = fingerprintData
        
        // Increment counter before using it
        context.logCount += 1
        let currentDiveNumber = context.logCount
        logInfo("📊 Processing dive #\(currentDiveNumber)")
        
        // Update progress with the current dive number
        DispatchQueue.main.async {
            context.viewModel.updateProgress(
                current: currentDiveNumber,
                total: nil
            )
        }
        
        // Get device family and model
        if let deviceInfo = DeviceConfiguration.identifyDevice(name: context.deviceName) {
            do {
                let diveData = try GenericParser.parseDiveData(
                    family: deviceInfo.family,
                    model: deviceInfo.model,
                    diveNumber: currentDiveNumber,
                    diveData: data,
                    dataSize: Int(size)
                )
                
                DispatchQueue.main.async {
                    context.viewModel.dives.append(diveData)
                }
            } catch {
                logError("❌ Failed to parse dive #\(currentDiveNumber): \(error)")
                return 0 // Return 0 on parsing error
            }
        } else {
            logError("❌ Failed to identify device family for \(context.deviceName)")
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
        
        let context = CallbackContext(
            viewModel: viewModel,
            deviceName: deviceName
        )
        
        // Convert context to UnsafeMutableRawPointer
        let contextPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(context).toOpaque())
        
        DispatchQueue.global(qos: .userInitiated).async {
            logInfo("🔄 Starting dive enumeration...")
            let status = dc_device_foreach(device, diveCallbackClosure, contextPtr)
            
            // Release the context after we're done
            Unmanaged<CallbackContext>.fromOpaque(contextPtr).release()
            
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
        
        // Update timer check
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if devicePtr.pointee.have_progress != 0 {
                onProgress?(
                    Int(devicePtr.pointee.progress.current),
                    Int(devicePtr.pointee.progress.maximum)
                )
            }
            
            switch viewModel.progress {
            case .completed:
                timer.invalidate()
            case .error:
                timer.invalidate()
            default:
                break
            }
        }
    }
} 