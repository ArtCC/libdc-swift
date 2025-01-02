import Foundation
import Combine

public class DiveDataViewModel: ObservableObject {
    @Published public var dives: [DiveData] = []
    @Published public var status: String = ""
    @Published public var progress: DownloadProgress = .idle
    @Published public var hasNewDives: Bool = false
    
    // Key format: "fingerprint_{deviceType}_{serial}"
    private let fingerprintKeyPrefix = "fingerprint_"
    
    private struct StoredFingerprint: Codable {
        let deviceType: String
        let serial: String
        let fingerprint: Data
        let timestamp: Date
    }
    
    private let fingerprintKey = "DeviceFingerprints"
    
    public init() {}
    
    private func loadStoredFingerprints() -> [StoredFingerprint] {
        guard let data = UserDefaults.standard.data(forKey: fingerprintKey),
              let fingerprints = try? JSONDecoder().decode([StoredFingerprint].self, from: data) else {
            return []
        }
        return fingerprints
    }
    
    private func saveStoredFingerprints(_ fingerprints: [StoredFingerprint]) {
        if let data = try? JSONEncoder().encode(fingerprints) {
            UserDefaults.standard.set(data, forKey: fingerprintKey)
        }
    }
    
    private func normalizeDeviceType(_ deviceType: String) -> String {
        // Try to find matching descriptor from libdivecomputer
        var descriptor: OpaquePointer?
        let status = find_matching_descriptor(
            &descriptor,
            DC_FAMILY_NULL, // Use null family to match by name only
            0,             // Model 0 to match by name only
            deviceType     // Device name to match
        )
        
        // If we found a matching descriptor, use its product name
        if status == DC_STATUS_SUCCESS,
           let desc = descriptor,
           let product = dc_descriptor_get_product(desc) {
            let normalizedName = String(cString: product)
            dc_descriptor_free(desc)
            return normalizedName
        }
        
        // If no match found, fall back to basic string parsing
        let components = deviceType.split(separator: " ")
        
        // If single component, return as is
        if components.count == 1 {
            return String(components[0])
        }
        
        // Remove any serial numbers or identifiers (typically numeric)
        let nonNumericComponents = components.filter { !$0.allSatisfy { $0.isNumber } }
        
        // Take the last non-numeric component as the model name
        if let modelName = nonNumericComponents.last {
            return String(modelName)
        }
        
        // Fallback to original string if all else fails
        return deviceType
    }
    
    public func getFingerprint(forDeviceType deviceType: String, serial: String) -> Data? {
        let fingerprints = loadStoredFingerprints()
        logInfo("🔍 Looking up fingerprint - stored count: \(fingerprints.count)")
        
        let normalizedType = normalizeDeviceType(deviceType)
        for fp in fingerprints {
            let storedType = normalizeDeviceType(fp.deviceType)
            logInfo("📍 Stored: type='\(fp.deviceType)' normalized='\(storedType)' serial='\(fp.serial)' size=\(fp.fingerprint.count)")
        }
        
        let matches = fingerprints.filter { 
            normalizeDeviceType($0.deviceType) == normalizedType && 
            $0.serial == serial 
        }
        
        let found = matches
            .filter { !$0.fingerprint.isEmpty }
            .sorted { $0.timestamp > $1.timestamp }
            .first
        
        if let found = found {
            logInfo("✅ Found matching fingerprint: size=\(found.fingerprint.count)")
        } else {
            logInfo("❌ No matching fingerprint found for type='\(deviceType)' normalized='\(normalizedType)' serial='\(serial)'")
        }
        
        return found?.fingerprint
    }
    
    public func saveFingerprint(_ fingerprint: Data, deviceType: String, serial: String) {
        guard !fingerprint.isEmpty else {
            logWarning("⚠️ Attempted to save empty fingerprint - ignoring")
            return
        }
        
        let normalizedType = normalizeDeviceType(deviceType)
        logInfo("💾 Saving fingerprint - type='\(deviceType)' normalized='\(normalizedType)' serial='\(serial)' size=\(fingerprint.count)")
        
        var fingerprints = loadStoredFingerprints()
        
        // Use normalized type for comparison
        fingerprints.removeAll { 
            normalizeDeviceType($0.deviceType) == normalizedType && 
            $0.serial == serial 
        }
        
        let newFingerprint = StoredFingerprint(
            deviceType: deviceType,
            serial: serial,
            fingerprint: fingerprint,
            timestamp: Date()
        )
        fingerprints.append(newFingerprint)
        saveStoredFingerprints(fingerprints)
        objectWillChange.send() 
        
        logInfo("✅ Fingerprint saved successfully")
    }
    
    public func clearFingerprint(forDeviceType type: String, serial: String) {
        var fingerprints = loadStoredFingerprints()
        let normalizedType = normalizeDeviceType(type)
        
        // Use normalized type for comparison
        fingerprints.removeAll { 
            normalizeDeviceType($0.deviceType) == normalizedType && 
            $0.serial == serial 
        }
        saveStoredFingerprints(fingerprints)
        objectWillChange.send() 
        logInfo("🗑️ Cleared fingerprint for \(type) (\(serial))")
    }
    
    public func clearAllFingerprints() {
        UserDefaults.standard.removeObject(forKey: fingerprintKey)
        objectWillChange.send()
        logInfo("🗑️ Cleared all fingerprints")
    }
    
    public func getFingerprintInfo(forDeviceType type: String, serial: String) -> Date? {
        let fingerprints = loadStoredFingerprints()
        return fingerprints.first { 
            $0.deviceType == type && $0.serial == serial 
        }?.timestamp
    }
    
    public enum DownloadProgress: CustomStringConvertible, Equatable {
        case idle
        case inProgress(current: Int)
        case completed
        case cancelled
        case error(String)
        
        public var description: String {
            switch self {
            case .idle:
                return "Ready"
            case .inProgress:
                return ""
            case .completed:
                return "Completed"
            case .cancelled:
                return "Cancelled"
            case .error(let message):
                return "Error: \(message)"
            }
        }
        
        public static func == (lhs: DownloadProgress, rhs: DownloadProgress) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle):
                return true
            case (.completed, .completed):
                return true
            case (.cancelled, .cancelled):
                return true
            case let (.inProgress(current1), .inProgress(current2)):
                return current1 == current2
            case let (.error(message1), .error(message2)):
                return message1 == message2
            default:
                return false
            }
        }
    }
    
    public func addDive(number: Int, year: Int, month: Int, day: Int, 
                       hour: Int, minute: Int, second: Int,
                       maxDepth: Double, temperature: Double) {
        let components = DateComponents(year: year, month: month, day: day,
                                     hour: hour, minute: minute, second: second)
        if let date = Calendar.current.date(from: components) {
            let dive = DiveData(
                number: number,
                datetime: date,
                maxDepth: maxDepth,
                divetime: 0,
                temperature: temperature,
                profile: [],
                tankPressure: [],
                gasMix: nil,
                gasMixCount: nil,
                salinity: nil,
                atmospheric: 1.0,
                surfaceTemperature: nil,
                minTemperature: nil,
                maxTemperature: nil,
                tankCount: nil,
                tanks: nil,
                diveMode: .openCircuit,
                decoModel: nil,
                location: nil,
                rbt: nil,
                heartbeat: nil,
                bearing: nil,
                setpoint: nil,
                ppo2Readings: [],
                cns: nil,
                decoStop: nil
            )
            DispatchQueue.main.async {
                self.dives.append(dive)
                if case .inProgress = self.progress {
                    self.progress = .inProgress(current: self.dives.count)
                }
            }
        }
    }
    
    public func updateStatus(_ newStatus: String) {
        DispatchQueue.main.async {
            self.status = newStatus
        }
    }
    
    public func updateProgress(current: Int) {
        DispatchQueue.main.async {
            self.status = "Downloading Dive #\(current)"
            self.progress = .inProgress(current: current)
        }
    }
    
    public func setError(_ message: String) {
        DispatchQueue.main.async {
            self.progress = .error(message)
        }
    }
    
    public func clear() {
        DispatchQueue.main.async {
            self.dives.removeAll()
            self.hasNewDives = false
            if case .idle = self.progress {
                self.status = ""
            }
            self.progress = .idle
        }
    }
    
    public func setDetailedError(_ message: String, status: dc_status_t) {
        DispatchQueue.main.async {
            let statusDescription = switch status {
            case DC_STATUS_SUCCESS: "Success"
            case DC_STATUS_DONE: "Done"
            case DC_STATUS_UNSUPPORTED: "Unsupported Operation"
            case DC_STATUS_INVALIDARGS: "Invalid Arguments"
            case DC_STATUS_NOMEMORY: "Out of Memory"
            case DC_STATUS_NODEVICE: "No Device"
            case DC_STATUS_NOACCESS: "No Access"
            case DC_STATUS_IO: "Communication Error"
            case DC_STATUS_TIMEOUT: "Timeout"
            case DC_STATUS_PROTOCOL: "Protocol Error"
            case DC_STATUS_DATAFORMAT: "Data Format Error"
            case DC_STATUS_CANCELLED: "Cancelled"
            default: "Unknown Error (\(status))"
            }
            
            self.progress = .error("\(message): \(statusDescription)")
        }
    }
    
    public func appendDives(_ newDives: [DiveData]) {
        DispatchQueue.main.async {
            if !newDives.isEmpty {
                self.hasNewDives = true
            }
            self.dives.append(contentsOf: newDives)
            if case .inProgress = self.progress {
                self.progress = .inProgress(current: self.dives.count)
            }
        }
    }
    
    func forgetDevice(deviceType: String, serial: String) {
        if var storedDevices = DeviceStorage.shared.getAllStoredDevices() {
            storedDevices.removeAll { device in
                device.name == deviceType 
            }
            DeviceStorage.shared.updateStoredDevices(storedDevices)
        }
        clearFingerprint(forDeviceType: deviceType, serial: serial)
        objectWillChange.send() 
        
        logInfo("🗑️ Forgot device and cleared fingerprint for \(deviceType) (\(serial))")
    }
    
    public func isDownloadOnlyNewDivesEnabled(forDeviceType deviceType: String, serial: String) -> Bool {
        let fingerprints = loadStoredFingerprints()
        if let storedFingerprint = fingerprints.first(where: { $0.deviceType == deviceType && $0.serial == serial }),
           !storedFingerprint.fingerprint.isEmpty {
            logInfo("🔍 Download only new dives is enabled for \(deviceType) (\(serial))")
            logInfo("📍 Current stored fingerprint: \(storedFingerprint.fingerprint.hexString)")
            return true
        }
        logInfo("🔍 Download only new dives is disabled for \(deviceType) (\(serial))")
        return false
    }
} 
