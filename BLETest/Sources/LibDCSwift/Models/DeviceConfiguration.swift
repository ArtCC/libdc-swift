import Foundation

@objc public class DeviceConfiguration: NSObject {
    public enum DeviceFamily: UInt32 {
        case shearwaterPredator = 655360  // (10 << 16)
        case shearwaterPetrel = 655361    // (10 << 16) + 1
        case suuntoEonSteel = 65541       // (1 << 16) + 5
        
        var asDCFamily: UInt32 {
            return self.rawValue
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
    
    @objc public static func openBLEDevice(name: String, deviceAddress: String) -> Bool {
        var familyUInt: UInt32 = 0
        var model: UInt32 = 0
        
        let status = identify_ble_device(
            name.cString(using: .utf8),
            &familyUInt,
            &model
        )
        
        guard status == DC_STATUS_SUCCESS else {
            return false
        }
        
        var deviceData = device_data_t()
        let openStatus = open_ble_device(
            &deviceData,
            deviceAddress.cString(using: .utf8),
            dc_family_t(familyUInt),
            model
        )
        
        return openStatus == DC_STATUS_SUCCESS
    }
    
    public static func identifyDevice(name: String) -> (family: DeviceFamily, model: UInt32)? {
        return DeviceFamily.fromName(name) ?? identifyDeviceFromDescriptor(name: name)
    }
    
    public static func identifyDeviceFromDescriptor(name: String) -> (family: DeviceFamily, model: UInt32)? {
        var familyUInt: UInt32 = 0
        var model: UInt32 = 0
        
        let status = identify_ble_device(
            name.cString(using: .utf8),
            &familyUInt,
            &model
        )
        
        guard status == DC_STATUS_SUCCESS,
              let deviceFamily = DeviceFamily(rawValue: familyUInt) else {
            return nil
        }
        
        return (deviceFamily, model)
    }
}
