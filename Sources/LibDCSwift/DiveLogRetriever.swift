import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// A class responsible for retrieving dive logs from connected dive computers.
/// Handles the communication with the device, data parsing, and progress tracking.
public class DiveLogRetriever {
    /// Internal context class to maintain state during dive log retrieval.
    private class CallbackContext {
        var logCount: Int = 1 /// Current dive log being processed
        var totalLogs: Int = 0 /// Total number of dive logs to process
        let viewModel: DiveDataViewModel /// View model to update UI and store dive data
        var lastFingerprint: Data? /// Fingerprint of the last processed dive
        let deviceName: String /// Name of the device being processed
        var isCancelled: Bool = false  /// Flag to indicate if the retrieval process was cancelled 
        var newDives: [DiveData] = [] /// Array to store newly retrieved dives
        
        init(viewModel: DiveDataViewModel, deviceName: String) {
            self.viewModel = viewModel
            self.deviceName = deviceName
        }
    }

    /// C-compatible callback closure for processing individual dive logs.
    /// This is called by libdivecomputer for each dive found on the device.
    /// - Parameters:
    ///   - data: Raw dive data
    ///   - size: Size of the dive data
    ///   - fingerprint: Unique identifier for the dive
    ///   - fsize: Size of the fingerprint
    ///   - userdata: Context data for the callback
    /// - Returns: 1 if successful, 0 if failed
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
        
        context.logCount += 1
        return 1 
    }
    
    #if os(iOS)
    private static var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    #endif
    
    /// Retrieves dive logs from a connected dive computer.
    /// - Parameters:
    ///   - devicePtr: Pointer to the device data structure
    ///   - device: The CoreBluetooth peripheral representing the dive computer
    ///   - viewModel: View model to update UI and store dive data
    ///   - onProgress: Optional callback for progress updates
    ///   - completion: Called when retrieval completes or fails
    public static func retrieveDiveLogs(
        from devicePtr: UnsafeMutablePointer<device_data_t>,
        device: CBPeripheral,
        viewModel: DiveDataViewModel,
        onProgress: ((Int, Int) -> Void)? = nil,
        completion: @escaping (Bool) -> Void
    ) {
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

/// Extension to convert Data to hexadecimal string representation
extension Data {
    /// Returns a hexadecimal string representation of the data
    var hexString: String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}
