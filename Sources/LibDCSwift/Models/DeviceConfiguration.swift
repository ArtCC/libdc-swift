import Foundation
import Clibdivecomputer
import LibDCBridge

@objc public class DeviceConfiguration: NSObject {
    /// Represents the family of dive computers that support BLE communication.
    /// Only includes device families that have BLE-capable models.
    public enum DeviceFamily: String, Codable {
        case suuntoEonSteel
        case shearwaterPetrel
        case hwOstc3
        case uwatecSmart
        case oceanicAtom2
        case pelagicI330R
        case maresIconHD
        case deepsixExcursion
        case deepbluCosmiq
        case oceansS1
        case mcleanExtreme
        case divesoftFreedom
        case cressiGoa
        case diveSystem
        
        /// Converts the Swift enum to libdivecomputer's dc_family_t type
        var asDCFamily: dc_family_t {
            switch self {
            case .suuntoEonSteel: return DC_FAMILY_SUUNTO_EONSTEEL
            case .shearwaterPetrel: return DC_FAMILY_SHEARWATER_PETREL
            case .hwOstc3: return DC_FAMILY_HW_OSTC3
            case .uwatecSmart: return DC_FAMILY_UWATEC_SMART
            case .oceanicAtom2: return DC_FAMILY_OCEANIC_ATOM2
            case .pelagicI330R: return DC_FAMILY_PELAGIC_I330R
            case .maresIconHD: return DC_FAMILY_MARES_ICONHD
            case .deepsixExcursion: return DC_FAMILY_DEEPSIX_EXCURSION
            case .deepbluCosmiq: return DC_FAMILY_DEEPBLU_COSMIQ
            case .oceansS1: return DC_FAMILY_OCEANS_S1
            case .mcleanExtreme: return DC_FAMILY_MCLEAN_EXTREME
            case .divesoftFreedom: return DC_FAMILY_DIVESOFT_FREEDOM
            case .cressiGoa: return DC_FAMILY_CRESSI_GOA
            case .diveSystem: return DC_FAMILY_DIVESYSTEM_IDIVE
            case .maresIconHD: return DC_FAMILY_MARES_ICONHD
            }
        }
        
        /// Creates a DeviceFamily instance from libdivecomputer's dc_family_t type
        /// - Parameter dcFamily: The dc_family_t value to convert
        /// - Returns: The corresponding DeviceFamily case, or nil if not supported
        init?(dcFamily: dc_family_t) {
            switch dcFamily {
            case DC_FAMILY_SUUNTO_EONSTEEL: self = .suuntoEonSteel
            case DC_FAMILY_SHEARWATER_PETREL: self = .shearwaterPetrel
            case DC_FAMILY_HW_OSTC3: self = .hwOstc3
            case DC_FAMILY_UWATEC_SMART: self = .uwatecSmart
            case DC_FAMILY_OCEANIC_ATOM2: self = .oceanicAtom2
            case DC_FAMILY_PELAGIC_I330R: self = .pelagicI330R
            case DC_FAMILY_MARES_ICONHD: self = .maresIconHD
            case DC_FAMILY_DEEPSIX_EXCURSION: self = .deepsixExcursion
            case DC_FAMILY_DEEPBLU_COSMIQ: self = .deepbluCosmiq
            case DC_FAMILY_OCEANS_S1: self = .oceansS1
            case DC_FAMILY_MCLEAN_EXTREME: self = .mcleanExtreme
            case DC_FAMILY_DIVESOFT_FREEDOM: self = .divesoftFreedom
            case DC_FAMILY_CRESSI_GOA: self = .cressiGoa
            case DC_FAMILY_DIVESYSTEM_IDIVE: self = .diveSystem
            case DC_FAMILY_MARES_ICONHD: self = .maresIconHD
            default: return nil
            }
        }
    }
    
    /// Known BLE service UUIDs for supported dive computers.
    /// Used for device discovery and identification.
    private static let knownServiceUUIDs: [CBUUID] = [
        CBUUID(string: "0000fefb-0000-1000-8000-00805f9b34fb"), // Heinrichs-Weikamp Telit/Stollmann
        CBUUID(string: "2456e1b9-26e2-8f83-e744-f34f01e9d701"), // Heinrichs-Weikamp U-Blox
        CBUUID(string: "544e326b-5b72-c6b0-1c46-41c1bc448118"), // Mares BlueLink Pro
        CBUUID(string: "6e400001-b5a3-f393-e0a9-e50e24dcca9e"), // Nordic Semi UART
        CBUUID(string: "98ae7120-e62e-11e3-badd-0002a5d5c51b"), // Suunto EON Steel/Core
        CBUUID(string: "cb3c4555-d670-4670-bc20-b61dbc851e9a"), // Pelagic i770R/i200C
        CBUUID(string: "ca7b0001-f785-4c38-b599-c7c5fbadb034"), // Pelagic i330R/DSX
        CBUUID(string: "fdcdeaaa-295d-470e-bf15-04217b7aa0a0"), // ScubaPro G2/G3
        CBUUID(string: "fe25c237-0ece-443c-b0aa-e02033e7029d"), // Shearwater Perdix/Teric
        CBUUID(string: "0000fcef-0000-1000-8000-00805f9b34fb")  // Divesoft Freedom
    ]
    
    /// Returns an array of known BLE service UUIDs for supported dive computers.
    /// - Returns: Array of CBUUIDs representing known service UUIDs
    public static func getKnownServiceUUIDs() -> [CBUUID] {
        return knownServiceUUIDs
    }
    
    /// Attempts to open a BLE connection to a dive computer.
    /// This function will try multiple methods to identify and connect to the device:
    /// 1. Use stored device information if available
    /// 2. Use descriptor system to identify device
    /// 3. Fall back to libdivecomputer's identify_ble_device
    /// - Parameters:
    ///   - name: The advertised name of the BLE device
    ///   - deviceAddress: The device's UUID/MAC address
    /// - Returns: True if connection was successful, false otherwise
    @objc public static func openBLEDevice(name: String, deviceAddress: String) -> Bool {
        logDebug("Attempting to open BLE device: \(name) at address: \(deviceAddress)")
        
        // Allocate device data first
        let deviceData = UnsafeMutablePointer<device_data_t>.allocate(capacity: 1)
        deviceData.initialize(to: device_data_t())
        
        // Try to get stored device info first
        if let storedDevice = DeviceStorage.shared.getStoredDevice(uuid: deviceAddress) {
            logDebug("Found stored device configuration - Family: \(storedDevice.family), Model: \(storedDevice.model)")
            let openStatus = open_ble_device(
                deviceData,
                deviceAddress.cString(using: .utf8),
                storedDevice.family.asDCFamily,
                storedDevice.model
            )
            
            if openStatus == DC_STATUS_SUCCESS {
                logDebug("Successfully opened device using stored configuration")
                logDebug("Device data pointer allocated at: \(String(describing: deviceData))")
                CoreBluetoothManager.shared.openedDeviceDataPtr = deviceData
                return true
            }
            logDebug("Failed to open with stored config (status: \(openStatus)), falling back to identification")
        }
        
        // Use descriptor system to identify device
        if let (family, model) = fromName(name) {
            let openStatus = open_ble_device(
                deviceData,
                deviceAddress.cString(using: .utf8),
                family.asDCFamily,
                model
            )
            
            if openStatus == DC_STATUS_SUCCESS {
                logDebug("Successfully opened device with descriptor configuration")
                logDebug("Device data pointer allocated at: \(String(describing: deviceData))")
                CoreBluetoothManager.shared.openedDeviceDataPtr = deviceData
                return true
            }
        }
        
        // Fall back to libdivecomputer's identify_ble_device
        var family: dc_family_t = DC_FAMILY_NULL
        var model: UInt32 = 0
        
        let status = identify_ble_device(
            name.cString(using: .utf8),
            &family,
            &model
        )
        
        guard status == DC_STATUS_SUCCESS else {
            logError("Failed to identify device: \(status)")
            deviceData.deallocate()
            return false
        }
        
        logDebug("Device identified successfully - Family: \(family), Model: \(model)")
        
        let openStatus = open_ble_device(
            deviceData,
            deviceAddress.cString(using: .utf8),
            family,
            model
        )
        
        if openStatus == DC_STATUS_SUCCESS {
            logDebug("Successfully opened device with new configuration")
            logDebug("Device data pointer allocated at: \(String(describing: deviceData))")
            CoreBluetoothManager.shared.openedDeviceDataPtr = deviceData
            return true
        } else {
            logError("Failed to open device: \(openStatus)")
            deviceData.deallocate()
            return false
        }
    }
    
    /// Attempts to identify a dive computer's family and model from its name.
    /// This function tries two methods:
    /// 1. Use libdivecomputer's descriptor system
    /// 2. Fall back to libdivecomputer's identify_ble_device
    /// - Parameter name: The advertised name of the BLE device
    /// - Returns: A tuple containing the device family and model number, or nil if not identified
    public static func identifyDevice(name: String) -> (family: DeviceFamily, model: UInt32)? {
        return fromName(name) ?? identifyDeviceFromDescriptor(name: name)
    }
    
    /// Attempts to identify a device's family and model number from its name using libdivecomputer's descriptor system.
    /// Only considers BLE-capable devices.
    /// - Parameter name: The device name to identify
    /// - Returns: A tuple containing the device family and model number, or nil if not identified
    static func fromName(_ name: String) -> (family: DeviceFamily, model: UInt32)? {
        if let descriptor = findMatchingDescriptor(for: name) {
            let family = dc_descriptor_get_type(descriptor)
            let model = dc_descriptor_get_model(descriptor)
            
            if let deviceFamily = DeviceFamily(dcFamily: family) {
                return (deviceFamily, model)
            }
        }
        return nil
    }
    
    /// Returns a human-readable display name for a device using libdivecomputer's vendor and product information.
    /// Only considers BLE-capable devices.
    /// - Parameter name: The device name to get display name for
    /// - Returns: A formatted string containing the vendor and product name, or "Unknown Device" if not found
    public static func getDeviceDisplayName(from name: String) -> String {
        if let descriptor = findMatchingDescriptor(for: name),
           let vendor = dc_descriptor_get_vendor(descriptor),
           let product = dc_descriptor_get_product(descriptor) {
            return "\(String(cString: vendor)) \(String(cString: product))"
        }
        return "Unknown Device"
    }
    
    /// Helper function that encapsulates the common descriptor iteration logic.
    /// Only considers BLE-capable devices.
    /// - Parameter name: The device name to find a descriptor for
    /// - Returns: A matching descriptor if found, nil otherwise
    private static func findMatchingDescriptor(for name: String) -> OpaquePointer? {
        var iterator: OpaquePointer?
        guard dc_descriptor_iterator(&iterator) == DC_STATUS_SUCCESS else {
            return nil
        }
        defer { dc_iterator_free(iterator) }
        
        let lowercaseName = name.lowercased()
        var descriptor: OpaquePointer?
        var matchingDescriptor: OpaquePointer?
        
        while dc_iterator_next(iterator, &descriptor) == DC_STATUS_SUCCESS {
            defer {
                if matchingDescriptor == nil {
                    dc_descriptor_free(descriptor)
                }
            }
            
            let transports = dc_descriptor_get_transports(descriptor)
            guard (transports & DC_TRANSPORT_BLE.rawValue) != 0 else { continue }
            
            guard let vendor = dc_descriptor_get_vendor(descriptor),
                  let product = dc_descriptor_get_product(descriptor) else { continue }
            
            let vendorStr = String(cString: vendor).lowercased()
            let productStr = String(cString: product).lowercased()
            if lowercaseName.contains(vendorStr) || lowercaseName.contains(productStr) {
                matchingDescriptor = descriptor
                break
            }
        }
        
        return matchingDescriptor
    }
    
    /// Attempts to identify a device using libdivecomputer's built-in identification function.
    /// Used as a fallback when descriptor-based identification fails.
    /// - Parameter name: The device name to identify
    /// - Returns: A tuple containing the device family and model number, or nil if not identified
    private static func identifyDeviceFromDescriptor(name: String) -> (family: DeviceFamily, model: UInt32)? {
        var family: dc_family_t = DC_FAMILY_NULL
        var model: UInt32 = 0
        
        let status = identify_ble_device(
            name.cString(using: .utf8),
            &family,
            &model
        )
        
        guard status == DC_STATUS_SUCCESS,
              let deviceFamily = DeviceFamily(dcFamily: family) else {
            return nil
        }
        
        return (deviceFamily, model)
    }
}
