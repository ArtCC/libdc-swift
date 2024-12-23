import Foundation

@objc public class DeviceConfiguration: NSObject {
    public enum DeviceFamily: Int {
        case suuntoEonSteel = 31    // DC_FAMILY_SUUNTO_EONSTEEL
        case shearwaterPetrel = 32  // DC_FAMILY_SHEARWATER_PETREL 
        case shearwaterPredator = 33 // DC_FAMILY_SHEARWATER_PREDATOR
        
        // Model numbers from descriptor.c
        public enum SuuntoModel: UInt32 {
            case eonSteel = 0
            case eonCore = 1
            case d5 = 2
            case eonSteelBlack = 3
        }
        
        public enum ShearwaterPetrelModel: UInt32 {
            case petrel = 3
            case petrel2 = 3
            case nerd = 4
            case perdix = 5
            case perdixAI = 6
            case nerd2 = 7
            case teric = 8
            case peregrine = 9
            case petrel3 = 10
            case perdix2 = 11
            case tern = 12
            case peregrineTX = 13
        }
        
        public enum ShearwaterPredatorModel: UInt32 {
            case predator = 2
        }
        
        public static func fromName(_ name: String) -> (family: DeviceFamily, model: UInt32)? {
            let lowercaseName = name.lowercased()
            
            // Suunto models
            if lowercaseName.contains("eon steel black") {
                return (.suuntoEonSteel, SuuntoModel.eonSteelBlack.rawValue)
            } else if lowercaseName.contains("eon steel") {
                return (.suuntoEonSteel, SuuntoModel.eonSteel.rawValue)
            } else if lowercaseName.contains("eon core") {
                return (.suuntoEonSteel, SuuntoModel.eonCore.rawValue)
            } else if lowercaseName.contains("d5") {
                return (.suuntoEonSteel, SuuntoModel.d5.rawValue)
            }
            
            // Shearwater Petrel models
            else if lowercaseName.contains("petrel 3") {
                return (.shearwaterPetrel, ShearwaterPetrelModel.petrel3.rawValue)
            } else if lowercaseName.contains("petrel 2") {
                return (.shearwaterPetrel, ShearwaterPetrelModel.petrel2.rawValue)
            } else if lowercaseName.contains("petrel") {
                return (.shearwaterPetrel, ShearwaterPetrelModel.petrel.rawValue)
            } else if lowercaseName.contains("perdix 2") {
                return (.shearwaterPetrel, ShearwaterPetrelModel.perdix2.rawValue)
            } else if lowercaseName.contains("perdix ai") {
                return (.shearwaterPetrel, ShearwaterPetrelModel.perdixAI.rawValue)
            } else if lowercaseName.contains("perdix") {
                return (.shearwaterPetrel, ShearwaterPetrelModel.perdix.rawValue)
            } else if lowercaseName.contains("nerd 2") {
                return (.shearwaterPetrel, ShearwaterPetrelModel.nerd2.rawValue)
            } else if lowercaseName.contains("nerd") {
                return (.shearwaterPetrel, ShearwaterPetrelModel.nerd.rawValue)
            } else if lowercaseName.contains("teric") {
                return (.shearwaterPetrel, ShearwaterPetrelModel.teric.rawValue)
            } else if lowercaseName.contains("peregrine tx") {
                return (.shearwaterPetrel, ShearwaterPetrelModel.peregrineTX.rawValue)
            } else if lowercaseName.contains("peregrine") {
                return (.shearwaterPetrel, ShearwaterPetrelModel.peregrine.rawValue)
            } else if lowercaseName.contains("tern") {
                return (.shearwaterPetrel, ShearwaterPetrelModel.tern.rawValue)
            }
            
            // Shearwater Predator models
            else if lowercaseName.contains("predator") {
                return (.shearwaterPredator, ShearwaterPredatorModel.predator.rawValue)
            }
            
            return nil
        }
    }
    
    @objc public static func openBLEDevice(name: String, deviceAddress: String) -> Bool {
        var family: dc_family_t = 0
        var model: UInt32 = 0
        var descriptor: OpaquePointer? = nil
        
        // Get the descriptor for this device
        let status = identify_ble_device(
            name.cString(using: .utf8),
            &family,
            &model,
            &descriptor
        )
        
        guard status == DC_STATUS_SUCCESS, let descriptor = descriptor else {
            return false
        }
        
        // Open device using descriptor
        var deviceData = device_data_t()
        let openStatus = open_ble_device_with_descriptor(&deviceData, deviceAddress.cString(using: .utf8), descriptor)
        
        // Free the descriptor
        dc_descriptor_free(descriptor)
        
        return openStatus == DC_STATUS_SUCCESS
    }
    
    public static func identifyDevice(name: String) -> (family: DeviceFamily, model: UInt32)? {
        return DeviceFamily.fromName(name) ?? identifyDeviceFromDescriptor(name: name)
    }
    
    public static func identifyDeviceFromDescriptor(name: String) -> (family: DeviceFamily, model: UInt32)? {
        var family: dc_family_t = 0
        var model: UInt32 = 0
        
        let status = identify_ble_device(
            name.cString(using: .utf8),
            &family,
            &model
        )
        
        guard status == DC_STATUS_SUCCESS,
              let deviceFamily = DeviceFamily(rawValue: Int(family)) else {
            return nil
        }
        
        return (deviceFamily, model)
    }
}
