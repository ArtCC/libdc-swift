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
        var hasNewDives: Bool = false  /// Flag to indicate if we've found new dives
        var storedFingerprint: Data?   /// Fingerprint of the stored dive
        var skippedDiveCount: Int = 0  /// Count of dives skipped due to fingerprint match
        var lastTimestamp: UInt64 = 0  // Add this to track timestamps
        weak var bluetoothManager: CoreBluetoothManager? /// Reference to BLE manager
        
        init(viewModel: DiveDataViewModel, deviceName: String, storedFingerprint: Data?, bluetoothManager: CoreBluetoothManager) {
            self.viewModel = viewModel
            self.deviceName = deviceName
            self.storedFingerprint = storedFingerprint
            self.bluetoothManager = bluetoothManager
            // Convert fingerprint to timestamp if available
            if let fingerprint = storedFingerprint {
                // Fingerprint is stored as big-endian 8-byte timestamp
                let bytes = [UInt8](fingerprint)
                if bytes.count == 8 {
                    lastTimestamp = UInt64(bytes[0]) << 56 |
                                   UInt64(bytes[1]) << 48 |
                                   UInt64(bytes[2]) << 40 |
                                   UInt64(bytes[3]) << 32 |
                                   UInt64(bytes[4]) << 24 |
                                   UInt64(bytes[5]) << 16 |
                                   UInt64(bytes[6]) << 8  |
                                   UInt64(bytes[7])
                }
            }
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
        
        // Check if download was cancelled
        if context.viewModel.progress == .cancelled || 
           context.bluetoothManager?.isRetrievingLogs == false {
            logInfo("🛑 Download cancelled - stopping enumeration")
            return 0  // Stop enumeration
        }
        
        // Store fingerprint of the current dive
        let fingerprintData = Data(bytes: fingerprint, count: Int(fsize))
        
        // Convert fingerprint to timestamp (big-endian 8-byte value)
        let bytes = [UInt8](fingerprintData)
        if bytes.count == 8 {
            let timestamp = UInt64(bytes[0]) << 56 |
                           UInt64(bytes[1]) << 48 |
                           UInt64(bytes[2]) << 40 |
                           UInt64(bytes[3]) << 32 |
                           UInt64(bytes[4]) << 24 |
                           UInt64(bytes[5]) << 16 |
                           UInt64(bytes[6]) << 8  |
                           UInt64(bytes[7])
            
            // Compare with stored timestamp
            if timestamp <= context.lastTimestamp {
                logInfo("🎯 Found dive with older/equal timestamp - stopping enumeration")
                return 0  // Stop enumeration for older dives
            }
            
            // This is a new dive, process it
            context.hasNewDives = true
            context.lastFingerprint = fingerprintData
            logInfo("📍 New dive fingerprint: \(fingerprintData.hexString) (timestamp: \(timestamp))")
            
            // Get the currentDiveNumber (adjusted for skipped dives)
            let currentDiveNumber = context.logCount
            logInfo("📊 Processing dive #\(currentDiveNumber)")
            
            // Update progress with the current dive number
            DispatchQueue.main.async {
                context.viewModel.updateProgress(current: currentDiveNumber)
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
                        context.viewModel.appendDives([diveData])  
                        context.viewModel.objectWillChange.send()
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
    ///   - bluetoothManager: Reference to BLE manager
    ///   - onProgress: Optional callback for progress updates
    ///   - completion: Called when retrieval completes or fails
    public static func retrieveDiveLogs(
        from devicePtr: UnsafeMutablePointer<device_data_t>,
        device: CBPeripheral,
        viewModel: DiveDataViewModel,
        bluetoothManager: CoreBluetoothManager,
        onProgress: ((Int, Int) -> Void)? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        let retrievalQueue = DispatchQueue(label: "com.libdcswift.retrieval", qos: .userInitiated)
        
        // Get stored fingerprint before starting retrieval
        let storedFingerprint = viewModel.getFingerprint(forDevice: device.identifier.uuidString)
        logInfo("📍 Retrieved stored fingerprint: \(storedFingerprint?.hexString ?? "none")")

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
                deviceName: device.name ?? "Unknown Device",
                storedFingerprint: storedFingerprint,
                bluetoothManager: bluetoothManager
            )
            
            let contextPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(context).toOpaque())
            
            // Set the fingerprint if we have one
            if let storedFingerprint = storedFingerprint {
                logInfo("🔍 Setting stored fingerprint for dive enumeration")
                let status = dc_device_set_fingerprint(
                    dcDevice,
                    [UInt8](storedFingerprint),
                    UInt32(storedFingerprint.count)
                )
                if status != DC_STATUS_SUCCESS {
                    logWarning("⚠️ Failed to set fingerprint with status: \(status)")
                }
            }

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
                    if context.hasNewDives {
                        if let lastFingerprint = context.lastFingerprint {
                            viewModel.saveFingerprint(lastFingerprint, forDevice: device)
                            logInfo("💾 Saved new fingerprint: \(lastFingerprint.hexString)")
                            viewModel.progress = .completed
                            completion(true)
                        }
                    } else {
                        logInfo("✨ No new dives found (all dives match stored fingerprint)")
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
