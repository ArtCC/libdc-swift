import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// A class responsible for retrieving dive logs from connected dive computers.
/// Handles the communication with the device, data parsing, and progress tracking.
public class DiveLogRetriever {
    private class CallbackContext {
        var logCount: Int = 1
        let viewModel: DiveDataViewModel
        var lastFingerprint: Data?
        let deviceName: String
        var deviceSerial: String?
        var isCancelled: Bool = false
        var hasNewDives: Bool = false
        weak var bluetoothManager: CoreBluetoothManager?
        var devicePtr: UnsafeMutablePointer<device_data_t>?
        var hasDeviceInfo: Bool = false
        var storedFingerprint: Data?
        
        init(viewModel: DiveDataViewModel, deviceName: String, storedFingerprint: Data?, bluetoothManager: CoreBluetoothManager) {
            self.viewModel = viewModel
            self.deviceName = deviceName
            self.storedFingerprint = storedFingerprint
            self.bluetoothManager = bluetoothManager
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
        
        let context = Unmanaged<CallbackContext>.fromOpaque(userdata).takeUnretainedValue()
        if context.viewModel.progress == .cancelled || 
           context.bluetoothManager?.isRetrievingLogs == false {
            logInfo("🛑 Download cancelled - stopping enumeration")
            return 0
        }
        
        if !context.hasDeviceInfo,
           let devicePtr = context.devicePtr,
           devicePtr.pointee.have_devinfo != 0 {
            let deviceSerial = String(format: "%08x", devicePtr.pointee.devinfo.serial)
            context.deviceSerial = deviceSerial
            context.hasDeviceInfo = true
        }
        
        let fingerprintData = Data(bytes: fingerprint, count: Int(fsize))
        if context.logCount == 1 {
            context.lastFingerprint = fingerprintData
            logInfo("📍 Stored fingerprint from newest dive: \(fingerprintData.hexString)")
        }
        
        if let storedFingerprint = context.storedFingerprint {
            if storedFingerprint == fingerprintData {
                logInfo("🎯 Found matching fingerprint - stopping enumeration")
                return 0
            }
        } else {
            logInfo("💡 No stored fingerprint - downloading all dives")
        }
        
        if let deviceInfo = DeviceConfiguration.identifyDevice(name: context.deviceName) {
            do {
                let diveData = try GenericParser.parseDiveData(
                    family: deviceInfo.family,
                    model: deviceInfo.model,
                    diveNumber: context.logCount,
                    diveData: data,
                    dataSize: Int(size)
                )
                
                DispatchQueue.main.async {
                    context.viewModel.appendDives([diveData])
                    context.viewModel.updateProgress(current: context.logCount)
                    logInfo("✅ Successfully parsed dive #\(context.logCount - 1)")
                }
            } catch {
                logError("❌ Failed to parse dive #\(context.logCount): \(error)")
                return 0
            }
        }
        
        context.logCount += 1
        context.hasNewDives = true
        return 1
    }
    
    #if os(iOS)
    private static var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    #endif
    
    /// C callback for fingerprint lookup
    private static let fingerprintLookup: @convention(c) (
        UnsafeMutableRawPointer?, 
        UnsafePointer<CChar>?, 
        UnsafePointer<CChar>?, 
        UnsafeMutablePointer<Int>?
    ) -> UnsafeMutablePointer<UInt8>? = { context, deviceType, serial, size in
        logInfo("🔍 Fingerprint lookup called")
        
        guard let context = context,
              let deviceType = deviceType,
              let serial = serial,
              let size = size else {
            logError("❌ Fingerprint lookup: Missing required parameters")
            return nil
        }
        
        let deviceTypeStr = String(cString: deviceType)
        let serialStr = String(cString: serial)
        logInfo("🔍 Looking up fingerprint for \(deviceTypeStr) (\(serialStr))")
        
        let viewModel = Unmanaged<DiveDataViewModel>.fromOpaque(context).takeUnretainedValue()
        
        if let fingerprint = viewModel.getFingerprint(
            forDeviceType: deviceTypeStr,
            serial: serialStr
        ) {
            logInfo("✅ Found stored fingerprint of size \(fingerprint.count)")
            size.pointee = fingerprint.count
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: fingerprint.count)
            fingerprint.copyBytes(to: buffer, count: fingerprint.count)
            return buffer
        }
        
        logInfo("ℹ️ No stored fingerprint found")
        return nil
    }
    
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
                storedFingerprint: nil, // We'll get this when we have device info
                bluetoothManager: bluetoothManager
            )
            context.devicePtr = devicePtr
            let contextPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(context).toOpaque())
            
            let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                if devicePtr.pointee.have_progress != 0 {
                    onProgress?(
                        Int(devicePtr.pointee.progress.current),
                        Int(devicePtr.pointee.progress.maximum)
                    )
                }
            }
            
            devicePtr.pointee.fingerprint_context = Unmanaged.passUnretained(viewModel).toOpaque()
            devicePtr.pointee.lookup_fingerprint = fingerprintLookup
            
            logInfo("🔄 Starting dive enumeration...")
            let enumStatus = dc_device_foreach(dcDevice, diveCallbackClosure, contextPtr)
            
            progressTimer.invalidate()
            DispatchQueue.main.async {
                if enumStatus == DC_STATUS_SUCCESS {
                    if context.hasNewDives {
                        if let lastFingerprint = context.lastFingerprint,
                           let deviceSerial = context.deviceSerial {
                            viewModel.saveFingerprint(
                                lastFingerprint,
                                deviceType: context.deviceName,
                                serial: deviceSerial
                            )
                            logInfo("💾 Saved new fingerprint: \(lastFingerprint.hexString)")
                            viewModel.progress = .completed
                            completion(true)
                        }
                    } else {
                        logInfo("✨ No new dives found")
                        viewModel.progress = .completed
                        completion(true)
                    }
                } else {
                    viewModel.setDetailedError("Error enumerating dives", status: enumStatus)
                    completion(false)
                }
                
                Unmanaged<CallbackContext>.fromOpaque(contextPtr).release()
                
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
    var hexString: String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}
