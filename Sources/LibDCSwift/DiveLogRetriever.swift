import Foundation
#if canImport(UIKit)
import UIKit
#endif

public class DiveLogRetriever {
    private class CallbackContext {
        var logCount: Int = 1
        var totalLogs: Int = 0
        let viewModel: DiveDataViewModel
        var lastFingerprint: Data?
        let deviceName: String
        var isCancelled: Bool = false  
        var newDives: [DiveData] = []
        
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

        // Get the currentDiveNumber
        let currentDiveNumber = context.logCount
        logInfo("📊 Processing dive #\(currentDiveNumber)")
        
        // Update progress with the current dive number
        DispatchQueue.main.async {
            context.viewModel.updateProgress(current: currentDiveNumber)
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
                    context.viewModel.appendDives([diveData])  
                    logInfo("✅ Successfully parsed and added dive #\(currentDiveNumber)")
                }
            } catch {
                logError("❌ Failed to parse dive #\(currentDiveNumber): \(error)")
                return 0
            }
        } else {
            logError("❌ Failed to identify device family for \(context.deviceName)")
            return 0
        }
        
        // Increment counter after using it
        context.logCount += 1
        return 1 // Return 1 on successful processing
    }
    
    #if os(iOS)
    private static var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    #endif
    
    public static func retrieveDiveLogs(
        from devicePtr: UnsafeMutablePointer<device_data_t>,
        device: CBPeripheral,
        viewModel: DiveDataViewModel,
        onProgress: ((Int, Int) -> Void)? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        // Create a dedicated background queue for dive log retrieval
        let retrievalQueue = DispatchQueue(label: "com.libdcswift.retrieval", qos: .userInitiated)
        
        #if os(iOS)
        backgroundTask = UIApplication.shared.beginBackgroundTask {
            endBackgroundTask()
            DispatchQueue.main.async {
                viewModel.setDetailedError("Background task expired", status: DC_STATUS_TIMEOUT)
                completion(false)
            }
        }
        #endif
        
        // Run the retrieval process in background
        retrievalQueue.async {
            guard let dcDevice = devicePtr.pointee.device else {
                DispatchQueue.main.async {
                    viewModel.setDetailedError("No device connection found", status: DC_STATUS_IO)
                    completion(false)
                }
                return
            }
            
            let context = CallbackContext(
                viewModel: viewModel,
                deviceName: device.name ?? "Unknown Device"
            )
            
            let contextPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(context).toOpaque())
            
            // Set up progress reporting on main thread
            let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                if devicePtr.pointee.have_progress != 0 {
                    onProgress?(
                        Int(devicePtr.pointee.progress.current),
                        Int(devicePtr.pointee.progress.maximum)
                    )
                }
            }
            
            // Start dive enumeration
            logInfo("🔄 Starting dive enumeration...")
            let status = dc_device_foreach(dcDevice, diveCallbackClosure, contextPtr)
            
            // Clean up
            Unmanaged<CallbackContext>.fromOpaque(contextPtr).release()
            progressTimer.invalidate()  // Stop the timer
            
            DispatchQueue.main.async {
                if status == DC_STATUS_SUCCESS {
                    if !context.newDives.isEmpty {
                        if let lastFingerprint = context.lastFingerprint {
                            viewModel.saveFingerprint(lastFingerprint, forDevice: device)
                            logInfo("💾 Saved new fingerprint: \(lastFingerprint.hexString)")
                        }
                        viewModel.progress = .completed
                        logDebug("✅ Dive retrieval completed successfully")
                        completion(true)
                    } else {
                        logWarning("⚠ No new dives found")
                        viewModel.progress = .completed
                        completion(true)
                    }
                } else {
                    viewModel.setDetailedError("Error enumerating dives", status: status)
                    completion(false)
                }
                
                #if os(iOS)
                endBackgroundTask()
                #endif
            }
        }
    }
    
    #if os(iOS)
    private static func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    #endif
} 

extension Data {
    var hexString: String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}
