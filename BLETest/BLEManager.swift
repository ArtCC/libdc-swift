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
    private let queue = DispatchQueue(label: "com.blemanager.queue")
    private let frameMarker: UInt8 = 0x7E
    
    // Add the device data property
    public var openedDeviceDataPtr: UnsafeMutablePointer<device_data_t>?
    
    private var connectionCompletion: ((Bool) -> Void)?
    
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
        return true  // Return immediately, connection status will be handled by delegate
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
    
    private func findNextCompleteFrame() -> Data? {
        var frameToReturn: Data? = nil
        
        queue.sync {
            // Look for frame start
            guard let startIndex = receivedData.firstIndex(of: frameMarker) else {
                return
            }
            
            // Look for frame end after start marker
            let afterStart = receivedData.index(after: startIndex)
            guard afterStart < receivedData.count,
                  let endIndex = receivedData[afterStart...].firstIndex(of: frameMarker) else {
                return
            }
            
            // Extract the complete frame including markers
            let frameEndIndex = receivedData.index(after: endIndex)
            let frame = receivedData[startIndex..<frameEndIndex]
            
            // Remove the frame from buffer
            receivedData.removeSubrange(startIndex..<frameEndIndex)
            
            frameToReturn = Data(frame)
        }
        
        return frameToReturn
    }
    
    @objc public func readData(_ size: Int) -> Data? {
        print("ReadData requested \(size) bytes. Currently buffered: \(receivedData.count) bytes")
        
        let startTime = Date()
        let timeout: TimeInterval = 30
        
        while true {
            var dataToReturn: Data?
            
            queue.sync {
                // If we have enough data, return the requested size
                if receivedData.count >= size {
                    print("Have enough data (\(receivedData.count) bytes) to satisfy read request of \(size) bytes")
                    dataToReturn = receivedData.prefix(size)
                    receivedData.removeSubrange(0..<size)
                }
            }
            
            if let data = dataToReturn {
                // Print the actual data being returned for debugging
                print("Returning \(data.count) bytes: \(data.hexEncodedString())")
                return data
            }
            
            // Check for timeout
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed > timeout {
                print("Read timeout after \(elapsed) seconds. Buffer contains: \(receivedData.hexEncodedString())")
                return nil
            }
            
            // Wait a bit for more data
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
    }

    @objc public func writeData(_ data: Data) -> Bool {
        guard let peripheral = self.peripheral,
              let characteristic = self.writeCharacteristic else { return false }
        
        logDebug("Writing \(data.count) bytes: \(data.hexEncodedString())")
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        return true
    }
    
    @objc public func close() {
        queue.sync {
            logInfo("Clearing \(receivedData.count) bytes from receive buffer")
            receivedData.removeAll()
        }
        
        // Update the cleanup code
        if let devicePtr = self.openedDeviceDataPtr {
            if devicePtr.pointee.device != nil {
                dc_device_close(devicePtr.pointee.device)
            }
            devicePtr.deallocate()
            self.openedDeviceDataPtr = nil
        }
        
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
            logInfo("Bluetooth is powered on")
        case .poweredOff:
            logWarning("Bluetooth is powered off")
        case .resetting:
            logWarning("Bluetooth is resetting")
        case .unauthorized:
            logError("Bluetooth is unauthorized")
        case .unsupported:
            logError("Bluetooth is unsupported")
        case .unknown:
            logWarning("Bluetooth state is unknown")
        @unknown default:
            logWarning("Unknown Bluetooth state")
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logInfo("Successfully connected to \(peripheral.name ?? "Unknown Device")")
        DispatchQueue.main.async {
            self.isPeripheralReady = true
            self.connectedDevice = peripheral
        }
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logError("Failed to connect to \(peripheral.name ?? "Unknown Device"): \(error?.localizedDescription ?? "No error description")")
        // You can post a notification or use any other method to inform about failed connection
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logInfo("Disconnected from \(peripheral.name ?? "unknown device")")
        if let error = error {
            logError("Disconnect error: \(error.localizedDescription)")
        }
        isPeripheralReady = false
        self.connectedDevice = nil
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if peripheral.name != nil {
            logDebug("Discovered \(peripheral.name ?? "unnamed device")")
            if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
                discoveredPeripherals.append(peripheral)
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            logError("Error discovering services: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else {
            logWarning("No services found")
            return
        }
        
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            logError("Error discovering characteristics: \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else {
            logWarning("No characteristics found for service: \(service.uuid)")
            return
        }
        
        for characteristic in characteristics {
            logDebug("Discovered characteristic: \(characteristic.uuid)")
            if characteristic.uuid == writeCharacteristicUUID {
                writeCharacteristic = characteristic
                logInfo("Write characteristic found")
            } else if characteristic.uuid == notifyCharacteristicUUID {
                notifyCharacteristic = characteristic
                logInfo("Notify characteristic found")
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            logError("Error receiving data: \(error.localizedDescription)")
            return
        }
        
        guard let data = characteristic.value else {
            logWarning("No data received from characteristic")
            return
        }
        
        // Log just the data size and first few bytes as a preview
        let preview = data.prefix(4).map { String(format: "%02x", $0) }.joined()
        logDebug("Received data: \(preview)... (\(data.count) bytes)")
        
        queue.sync {
            // Append new data to our buffer
            receivedData.append(data)
            if Logger.shared.shouldShowRawData {
                logDebug("Buffer: \(receivedData.hexEncodedString())")
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == writeCharacteristicUUID {
            if let error = error {
                logError("Error writing to characteristic: \(error.localizedDescription)")
            } else {
                logDebug("Successfully wrote to characteristic")
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == notifyCharacteristicUUID {
            if let error = error {
                logError("Error changing notification state: \(error.localizedDescription)")
            } else {
                logInfo("Notification state updated: \(characteristic.isNotifying ? "enabled" : "disabled")")
            }
        }
    }

    @objc public func readDataPartial(_ requested: Int) -> Data? {
        let startTime = Date()
        let partialTimeout: TimeInterval = 5
        
        while true {
            var outData: Data? = nil
            queue.sync {
                if receivedData.count > 0 {
                    let amount = min(requested, receivedData.count)
                    outData = receivedData.prefix(amount)
                    receivedData.removeSubrange(0..<amount)
                }
            }
            
            if let data = outData {
                return data
            }
            
            if Date().timeIntervalSince(startTime) > partialTimeout {
                return nil
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
    }
}

extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}
