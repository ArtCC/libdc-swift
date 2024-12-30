import Foundation
import Clibdivecomputer
import LibDCBridge

@objc public class DeviceConfiguration: NSObject {
    public enum DeviceFamily: String, Codable {
        case shearwaterPredator
        case shearwaterPetrel
        case suuntoEonSteel
        
        var asDCFamily: dc_family_t {
            switch self {
            case .shearwaterPredator: return DC_FAMILY_SHEARWATER_PREDATOR
            case .shearwaterPetrel: return DC_FAMILY_SHEARWATER_PETREL
            case .suuntoEonSteel: return DC_FAMILY_SUUNTO_EONSTEEL
            }
        }
        
        init?(dcFamily: dc_family_t) {
            switch dcFamily {
            case DC_FAMILY_SHEARWATER_PREDATOR: self = .shearwaterPredator
            case DC_FAMILY_SHEARWATER_PETREL: self = .shearwaterPetrel
            case DC_FAMILY_SUUNTO_EONSTEEL: self = .suuntoEonSteel
            default: return nil
            }
        }
        
        static func fromName(_ name: String) -> (family: DeviceFamily, model: UInt32)? {
            let lowercaseName = name.lowercased()
            
            // Suunto models
            if lowercaseName.contains("eon steel black") {
                return (.suuntoEonSteel, SuuntoModel.eonSteelBlack)
            } else if lowercaseName.contains("eon steel") {
                return (.suuntoEonSteel, SuuntoModel.eonSteel)
            } else if lowercaseName.contains("eon core") {
                return (.suuntoEonSteel, SuuntoModel.eonCore)
            } else if lowercaseName.contains("d5") {
                return (.suuntoEonSteel, SuuntoModel.d5)
            }
            
            // Shearwater Petrel models
            else if lowercaseName.contains("petrel 3") {
                return (.shearwaterPetrel, ShearwaterPetrelModel.petrel3)
            } else if lowercaseName.contains("petrel 2") {
                return (.shearwaterPetrel, ShearwaterPetrelModel.petrel2)
            } else if lowercaseName.contains("petrel") {
                return (.shearwaterPetrel, ShearwaterPetrelModel.petrel)
            } else if lowercaseName.contains("perdix 2") {
                return (.shearwaterPetrel, ShearwaterPetrelModel.perdix2)
            } else if lowercaseName.contains("perdix ai") {
                return (.shearwaterPetrel, ShearwaterPetrelModel.perdixAI)
            } else if lowercaseName.contains("perdix") {
                return (.shearwaterPetrel, ShearwaterPetrelModel.perdix)
            } else if lowercaseName.contains("nerd 2") {
                return (.shearwaterPetrel, ShearwaterPetrelModel.nerd2)
            } else if lowercaseName.contains("nerd") {
                return (.shearwaterPetrel, ShearwaterPetrelModel.nerd)
            } else if lowercaseName.contains("teric") {
                return (.shearwaterPetrel, ShearwaterPetrelModel.teric)
            } else if lowercaseName.contains("peregrine tx") {
                return (.shearwaterPetrel, ShearwaterPetrelModel.peregrineTX)
            } else if lowercaseName.contains("peregrine") {
                return (.shearwaterPetrel, ShearwaterPetrelModel.peregrine)
            } else if lowercaseName.contains("tern") {
                return (.shearwaterPetrel, ShearwaterPetrelModel.tern)
            }
            
            // Shearwater Predator models
            else if lowercaseName.contains("predator") {
                return (.shearwaterPredator, ShearwaterPredatorModel.predator)
            }
            
            return nil
        }
    }
    
    public struct SuuntoModel {
        public static let eonSteel: UInt32 = 0
        public static let eonCore: UInt32 = 1
        public static let d5: UInt32 = 2
        public static let eonSteelBlack: UInt32 = 3
    }
    
    public struct ShearwaterPetrelModel {
        public static let petrel: UInt32 = 3
        public static let petrel2: UInt32 = 3
        public static let nerd: UInt32 = 4
        public static let perdix: UInt32 = 5
        public static let perdixAI: UInt32 = 6
        public static let nerd2: UInt32 = 7
        public static let teric: UInt32 = 8
        public static let peregrine: UInt32 = 9
        public static let petrel3: UInt32 = 10
        public static let perdix2: UInt32 = 11
        public static let tern: UInt32 = 12
        public static let peregrineTX: UInt32 = 13
    }
    
    public struct ShearwaterPredatorModel {
        public static let predator: UInt32 = 2
    }
    
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
    
    public static func getKnownServiceUUIDs() -> [CBUUID] {
        return knownServiceUUIDs
    }
    
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
            // If stored config fails, fall through to normal identification
        }
        
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
    
    public static func identifyDevice(name: String) -> (family: DeviceFamily, model: UInt32)? {
        return DeviceFamily.fromName(name) ?? identifyDeviceFromDescriptor(name: name)
    }
    
    public static func identifyDeviceFromDescriptor(name: String) -> (family: DeviceFamily, model: UInt32)? {
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
