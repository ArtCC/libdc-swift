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
        logInfo("📍 New dive fingerprint: \(fingerprintData.hexString)")
        
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
            logInfo("🔍 Device identified as family: \(deviceInfo.family), model: \(deviceInfo.model)")
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
                    logInfo("✅ Successfully added dive #\(currentDiveNumber) to view model")
                }
            } catch {
                logError("❌ Failed to parse dive #\(currentDiveNumber): \(error)")
                return 0
            }
        } else {
            logError("❌ Failed to identify device family for \(context.deviceName)")
            return 0
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
            logInfo("📍 Setting stored fingerprint: \(storedFingerprint.hexString)")
            let status = dc_device_set_fingerprint(
                device,
                Array(storedFingerprint),
                UInt32(storedFingerprint.count)
            )
            
            if status != DC_STATUS_SUCCESS {
                logWarning("⚠️ Failed to set fingerprint, will download all dives")
            } else {
                logInfo("✅ Set fingerprint, will only download new dives")
            }
        } else {
            logInfo("📍 No stored fingerprint found, will download all dives")
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
            logInfo("📊 Dive enumeration completed with status: \(status)")
            
            // Release the context after we're done
            Unmanaged<CallbackContext>.fromOpaque(contextPtr).release()
            
            DispatchQueue.main.async {
                if status == DC_STATUS_SUCCESS {
                    if context.logCount > 0 {
                        if let lastFingerprint = context.lastFingerprint {
                            viewModel.saveFingerprint(lastFingerprint)
                            logInfo("💾 Saved new fingerprint: \(lastFingerprint.hexString)")
                        }
                        viewModel.progress = .completed
                        completion(true)
                    } else {
                        logWarning("⚠️ Dive enumeration successful but no dives found")
                        viewModel.progress = .completed
                        completion(true)
                    }
                } else {
                    let errorMsg = "Error enumerating dives: \(status)"
                    logError("❌ \(errorMsg)")
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
                logInfo("Progress timer invalidated - Download completed")
            case .error:
                timer.invalidate()
                logInfo("Progress timer invalidated - Error occurred")
            default:
                break
            }
        }
    }
} 

extension Data {
    var hexString: String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}
