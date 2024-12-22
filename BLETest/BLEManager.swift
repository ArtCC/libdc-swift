import Foundation
import CoreBluetooth
import Combine

@objc public class CoreBluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @objc public static let shared = CoreBluetoothManager()
    @objc private var timeout: Int = -1 // default to no timeout

    @Published var centralManager: CBCentralManager!
    @Published var peripheral: CBPeripheral?
    @Published var discoveredPeripherals: [CBPeripheral] = []
    
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private let writeCharacteristicUUID = CBUUID(string: "C6339440-E62E-11E3-A5B3-0002A5D5C51B")
    private let notifyCharacteristicUUID = CBUUID(string: "D0FD6B80-E62E-11E3-A2E9-0002A5D5C51B")
    
    @Published var isPeripheralReady = false
    @Published @objc dynamic var connectedDevice: CBPeripheral?
    @Published var isScanning = false

    private var receivedData: Data = Data()
    private var readSemaphore = DispatchSemaphore(value: 0)
    
    private override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    @objc public func connectToDevice(_ address: String) -> Bool {
        guard let uuid = UUID(uuidString: address),
              let peripheral = centralManager.retrievePeripherals(withIdentifiers: [uuid]).first else {
            return false
        }
        
        self.peripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
        
        // Wait for connection (you might want to implement a timeout here)
        let startTime = Date()
        while self.connectedDevice == nil {
            if Date().timeIntervalSince(startTime) > 10 { // 10 second timeout
                return false
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        
        return self.connectedDevice != nil
    }
    
    @objc public func discoverServices() -> Bool {
        guard let peripheral = self.peripheral else { return false }
        
        peripheral.discoverServices(nil)
        
        // Wait for service discovery (you might want to implement a timeout here)
        while writeCharacteristic == nil || notifyCharacteristic == nil {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        
        return writeCharacteristic != nil && notifyCharacteristic != nil
    }

    @objc public func enableNotifications() -> Bool {
        guard let notifyCharacteristic = self.notifyCharacteristic,
              let peripheral = self.peripheral else { return false }
        
        peripheral.setNotifyValue(true, for: notifyCharacteristic)
        
        // Wait for notification to be enabled (you might want to implement a timeout here)
        while !notifyCharacteristic.isNotifying {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        
        return notifyCharacteristic.isNotifying
    }
    
    @objc public func readData(_ size: Int) -> Data? {
        // Wait for notification data instead of trying to read
        let result = readSemaphore.wait(timeout: .now() + .seconds(5))
        if result == .timedOut {
            return nil
        }
        
        let data = receivedData
        receivedData.removeAll()
        return data
    }

    @objc public func writeData(_ data: Data) -> Bool {
        guard let peripheral = self.peripheral,
              let characteristic = self.writeCharacteristic else { return false }
        
        // Write without response for Suunto D5
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        return true
    }
    
    @objc public func close() {
        if let connectedDevice = self.connectedDevice {
            centralManager.cancelPeripheralConnection(connectedDevice)
        }
    }
    
    public func startScanning() {
        centralManager.scanForPeripherals(withServices: nil, options: nil)
        isScanning = true
    }
    
    public func stopScanning() {
        centralManager.stopScan()
        isScanning = false
    }
    
    // MARK: - CBCentralManagerDelegate Methods
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("DEBUG: Bluetooth is powered on")
        case .poweredOff:
            print("DEBUG: Bluetooth is powered off")
        case .resetting:
            print("DEBUG: Bluetooth is resetting")
        case .unauthorized:
            print("DEBUG: Bluetooth is unauthorized")
        case .unsupported:
            print("DEBUG: Bluetooth is unsupported")
        case .unknown:
            print("DEBUG: Bluetooth state is unknown")
        @unknown default:
            print("DEBUG: Unknown Bluetooth state")
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("DEBUG: Successfully connected to \(peripheral.name ?? "Unknown Device")")
        isPeripheralReady = true
        self.connectedDevice = peripheral
        // You can post a notification or use any other method to inform about successful connection
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("DEBUG: Failed to connect to \(peripheral.name ?? "Unknown Device"): \(error?.localizedDescription ?? "No error description")")
        // You can post a notification or use any other method to inform about failed connection
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from \(peripheral.name ?? "unknown device")")
        if let error = error {
            print("Disconnect error: \(error.localizedDescription)")
        }
        isPeripheralReady = false
        self.connectedDevice = nil
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if peripheral.name != nil {
            print("Discovered \(peripheral.name ?? "unnamed device")")
            if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
                discoveredPeripherals.append(peripheral)
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
         if let error = error {
             print("Error discovering services: \(error.localizedDescription)")
             return
         }
         
         guard let services = peripheral.services else {
             print("No services found")
             return
         }
         
         for service in services {
             print("Discovered service: \(service.uuid)")
             peripheral.discoverCharacteristics(nil, for: service)
         }
     }

     public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
         if let error = error {
             print("Error discovering characteristics: \(error.localizedDescription)")
             return
         }
         
         guard let characteristics = service.characteristics else {
             print("No characteristics found for service: \(service.uuid)")
             return
         }
         
         for characteristic in characteristics {
             print("Discovered characteristic: \(characteristic.uuid)")
             if characteristic.uuid == writeCharacteristicUUID {
                 writeCharacteristic = characteristic
                 print("Write characteristic found")
             } else if characteristic.uuid == notifyCharacteristicUUID {
                 notifyCharacteristic = characteristic
                 print("Notify characteristic found")
                 peripheral.setNotifyValue(true, for: characteristic)
             }
         }
     }

     public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
         if characteristic.uuid == notifyCharacteristicUUID {
             if let error = error {
                 print("Error receiving notification: \(error.localizedDescription)")
                 readSemaphore.signal()
                 return
             }
             
             if let value = characteristic.value {
                 print("Received data from notify characteristic: \(value.hexEncodedString())")
                 // Append to our buffer
                 receivedData.append(value)
                 readSemaphore.signal()
             }
         }
     }

     public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
         if characteristic.uuid == writeCharacteristicUUID {
             if let error = error {
                 print("Error writing to characteristic: \(error.localizedDescription)")
             } else {
                 print("Successfully wrote to characteristic")
             }
         }
     }

     public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
         if characteristic.uuid == notifyCharacteristicUUID {
             if let error = error {
                 print("Error changing notification state: \(error.localizedDescription)")
             } else {
                 print("Notification state updated: \(characteristic.isNotifying ? "enabled" : "disabled")")
             }
         }
     }
}

extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}
