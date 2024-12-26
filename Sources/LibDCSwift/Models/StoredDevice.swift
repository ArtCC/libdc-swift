import Foundation
import CoreBluetooth

public class StoredDevice: Codable {
   let uuid: String
   let name: String
   let family: DeviceConfiguration.DeviceFamily
   let model: UInt32
   let lastConnected: Date
   
   init(uuid: String, name: String, family: DeviceConfiguration.DeviceFamily, model: UInt32) {
       self.uuid = uuid
       self.name = name
       self.family = family
       self.model = model
       self.lastConnected = Date()
   }
   
   // Manual Codable implementation
   private enum CodingKeys: String, CodingKey {
       case uuid
       case name
       case family
       case model
       case lastConnected
   }
   
   public required init(from decoder: Decoder) throws {
       let container = try decoder.container(keyedBy: CodingKeys.self)
       uuid = try container.decode(String.self, forKey: .uuid)
       name = try container.decode(String.self, forKey: .name)
       family = try container.decode(DeviceConfiguration.DeviceFamily.self, forKey: .family)
       model = try container.decode(UInt32.self, forKey: .model)
       lastConnected = try container.decode(Date.self, forKey: .lastConnected)
   }
   
   public func encode(to encoder: Encoder) throws {
       var container = encoder.container(keyedBy: CodingKeys.self)
       try container.encode(uuid, forKey: .uuid)
       try container.encode(name, forKey: .name)
       try container.encode(family, forKey: .family)
       try container.encode(model, forKey: .model)
       try container.encode(lastConnected, forKey: .lastConnected)
   }
}

@objc public class DeviceStorage: NSObject {
   public static let shared = DeviceStorage()
   
   private let defaults = UserDefaults.standard
   private let storageKey = "com.libdc.storedDevices"
   
   private var storedDevices: [StoredDevice] = []
   
   private override init() {
       super.init()
       loadDevices()
   }
   
   private func loadDevices() {
       if let data = defaults.data(forKey: storageKey),
          let devices = try? JSONDecoder().decode([StoredDevice].self, from: data) {
           storedDevices = devices
       }
   }
   
   private func saveDevices() {
       if let data = try? JSONEncoder().encode(storedDevices) {
           defaults.set(data, forKey: storageKey)
       }
   }
   
   public func storeDevice(uuid: String, name: String, family: DeviceConfiguration.DeviceFamily, model: UInt32) {
       let device = StoredDevice(uuid: uuid, name: name, family: family, model: model)
       if let index = storedDevices.firstIndex(where: { $0.uuid == uuid }) {
           storedDevices[index] = device
       } else {
           storedDevices.append(device)
       }
       saveDevices()
   }
   
   public func getStoredDevice(uuid: String) -> StoredDevice? {
       return storedDevices.first { $0.uuid == uuid }
   }
   
   public func removeDevice(uuid: String) {
       storedDevices.removeAll { $0.uuid == uuid }
       saveDevices()
   }
   
   public func getLastConnectedDevice() -> StoredDevice? {
       return storedDevices.max(by: { $0.lastConnected < $1.lastConnected })
   }
} 
