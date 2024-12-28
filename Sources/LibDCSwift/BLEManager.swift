import Foundation
import CoreBluetooth
import Clibdivecomputer
import LibDCBridge
import Combine

@objc(SerialService)
class SerialService: NSObject {
    @objc let uuid: String
    @objc let vendor: String
    @objc let product: String
    
    @objc init(uuid: String, vendor: String, product: String) {
        self.uuid = uuid
        self.vendor = vendor
        self.product = product
        super.init()
    }
}

extension CBUUID {
    var isStandardBluetooth: Bool {
        return self.data.count == 2
    }
}

@objc(CoreBluetoothManager)
public class CoreBluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @objc public static let shared = CoreBluetoothManager()
    @objc private var timeout: Int = -1 // default to no timeout

    @Published public var centralManager: CBCentralManager!
    @Published public var peripheral: CBPeripheral?
    @Published public var discoveredPeripherals: [CBPeripheral] = []
    
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    
    @Published public var isPeripheralReady = false
    @Published @objc dynamic public var connectedDevice: CBPeripheral?
    @Published public var isScanning = false

    private var receivedData: Data = Data()
    private let queue = DispatchQueue(label: "com.blemanager.queue")
    private let frameMarker: UInt8 = 0x7E
    
    private var _deviceDataPtr: UnsafeMutablePointer<device_data_t>?
    
    public var openedDeviceDataPtr: UnsafeMutablePointer<device_data_t>? {
        get {
            _deviceDataPtr
        }
        set {
            objectWillChange.send()
            _deviceDataPtr = newValue
            logDebug("Device data pointer \(newValue == nil ? "cleared" : "set")")
        }
    }
    
    @Published private var deviceDataPtrChanged = false
    
    public func hasValidDeviceDataPtr() -> Bool {
        return openedDeviceDataPtr != nil
    }
    
    private var connectionCompletion: ((Bool) -> Void)?
    
    private var totalBytesReceived: Int = 0
    private var lastDataReceived: Date?
    private var averageTransferRate: Double = 0
    
    @objc private let knownSerialServices: [SerialService] = [
        SerialService(uuid: "0000fefb-0000-1000-8000-00805f9b34fb", vendor: "Heinrichs-Weikamp", product: "Telit/Stollmann"),
        SerialService(uuid: "2456e1b9-26e2-8f83-e744-f34f01e9d701", vendor: "Heinrichs-Weikamp", product: "U-Blox"),
        SerialService(uuid: "544e326b-5b72-c6b0-1c46-41c1bc448118", vendor: "Mares", product: "BlueLink Pro"),
        SerialService(uuid: "6e400001-b5a3-f393-e0a9-e50e24dcca9e", vendor: "Nordic Semi", product: "UART"),
        SerialService(uuid: "98ae7120-e62e-11e3-badd-0002a5d5c51b", vendor: "Suunto", product: "EON Steel/Core"),
        SerialService(uuid: "cb3c4555-d670-4670-bc20-b61dbc851e9a", vendor: "Pelagic", product: "i770R/i200C"),
        SerialService(uuid: "ca7b0001-f785-4c38-b599-c7c5fbadb034", vendor: "Pelagic", product: "i330R/DSX"),
        SerialService(uuid: "fdcdeaaa-295d-470e-bf15-04217b7aa0a0", vendor: "ScubaPro", product: "G2/G3"),
        SerialService(uuid: "fe25c237-0ece-443c-b0aa-e02033e7029d", vendor: "Shearwater", product: "Perdix/Teric"),
        SerialService(uuid: "0000fcef-0000-1000-8000-00805f9b34fb", vendor: "Divesoft", product: "Freedom")
    ]
    
    private let excludedServices: Set<String> = [
        "00001530-1212-efde-1523-785feabcd123", // Nordic Upgrade
        "9e5d1e47-5c13-43a0-8635-82ad38a1386f", // Broadcom Upgrade #1
        "a86abc2d-d44c-442e-99f7-80059a873e36"  // Broadcom Upgrade #2
    ]
    
    private var preferredService: CBService?
    
    @Published public var isRetrievingLogs = false {
        didSet {
            objectWillChange.send()
        }
    }
    
    @Published public var currentRetrievalDevice: CBPeripheral? {
        didSet {
            objectWillChange.send()
        }
    }
    
    private override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    @objc internal func discoverServices() -> Bool {
        guard let peripheral = self.peripheral else { return false }
        
        peripheral.discoverServices(nil)
        
        // Wait for service discovery (you might want to implement a timeout here)
        while writeCharacteristic == nil || notifyCharacteristic == nil {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        
        return writeCharacteristic != nil && notifyCharacteristic != nil
    }

    @objc internal func enableNotifications() -> Bool {
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

    @objc public func writeData(_ data: Data) -> Bool {
        guard let peripheral = self.peripheral,
              let characteristic = self.writeCharacteristic else { return false }
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        return true
    }
    
    @objc public func close() {
        queue.sync {
            logInfo("Clearing \(receivedData.count) bytes from receive buffer")
            receivedData.removeAll()
        }
        
        if let devicePtr = self.openedDeviceDataPtr {
            logDebug("Closing device data pointer")
            if devicePtr.pointee.device != nil {
                logDebug("Closing device")
                dc_device_close(devicePtr.pointee.device)
            }
            logDebug("Deallocating device data pointer")
            devicePtr.deallocate()
            self.openedDeviceDataPtr = nil
        } else {
            logDebug("No device data pointer to close")
        }
        
        if let connectedDevice = self.connectedDevice {
            logDebug("Disconnecting peripheral")
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
        peripheral.delegate = self
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

        // Attempt to reconnect if this was a stored device
        if let storedDevice = DeviceStorage.shared.getStoredDevice(uuid: peripheral.identifier.uuidString) {
            logInfo("Attempting to reconnect to stored device")
            _ = DeviceConfiguration.openBLEDevice(
                name: storedDevice.name,
                deviceAddress: storedDevice.uuid
            )
        }
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
            if isExcludedService(service.uuid) {
                logInfo("Ignoring known firmware service: \(service.uuid)")
                continue
            }
            
            if let knownService = isKnownSerialService(service.uuid) {
                logInfo("Found known service: \(knownService.vendor) \(knownService.product)")
                preferredService = service
                writeCharacteristic = nil
                notifyCharacteristic = nil
            } else if !service.uuid.isStandardBluetooth {
                logInfo("Discovering characteristics for unknown service: \(service.uuid)")
            }
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
            if isWriteCharacteristic(characteristic) {
                logInfo("Found write characteristic: \(characteristic.uuid)")
                writeCharacteristic = characteristic
            }
            
            if isReadCharacteristic(characteristic) {
                logInfo("Found notify characteristic: \(characteristic.uuid)")
                notifyCharacteristic = characteristic
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
        if Logger.shared.shouldShowRawData {
            logDebug("Received data: \(preview)... (\(data.count) bytes)")
        }
        
        queue.sync {
            // Append new data to our buffer immediately
            receivedData.append(data)
            if Logger.shared.shouldShowRawData {
                logDebug("Buffer: \(receivedData.hexEncodedString())")
            }
            
            // Optional: Notify waiting readers that new data is available
            // This could be implemented via a condition variable or similar mechanism
        }
        
        updateTransferStats(data.count)
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            logError("Error writing to characteristic: \(error.localizedDescription)")
        } else {
            logDebug("Successfully wrote to characteristic")
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            logError("Error changing notification state: \(error.localizedDescription)")
        } else {
            logInfo("Notification state updated: \(characteristic.isNotifying ? "enabled" : "disabled")")
        }
    }

    @objc public func readDataPartial(_ requested: Int) -> Data? {
        let startTime = Date()
        let partialTimeout: TimeInterval = 1.0
        
        while true {
            var outData: Data?
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
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }
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

    private func updateTransferStats(_ newBytes: Int) {
        totalBytesReceived += newBytes
        
        if let last = lastDataReceived {
            let interval = Date().timeIntervalSince(last)
            if interval > 0 {
                let currentRate = Double(newBytes) / interval
                averageTransferRate = (averageTransferRate * 0.7) + (currentRate * 0.3)
                
                if totalBytesReceived % 1000 == 0 {  // Log every KB
                    logInfo("Transfer rate: \(Int(averageTransferRate)) bytes/sec")
                }
            }
        }
        
        lastDataReceived = Date()
    }

    private func isKnownSerialService(_ uuid: CBUUID) -> SerialService? {
        return knownSerialServices.first { service in
            uuid.uuidString.lowercased() == service.uuid.lowercased()
        }
    }
    
    private func isExcludedService(_ uuid: CBUUID) -> Bool {
        return excludedServices.contains(uuid.uuidString.lowercased())
    }
    
    private func isWriteCharacteristic(_ characteristic: CBCharacteristic) -> Bool {
        return characteristic.properties.contains(.write) ||
               characteristic.properties.contains(.writeWithoutResponse)
    }
    
    private func isReadCharacteristic(_ characteristic: CBCharacteristic) -> Bool {
        return characteristic.properties.contains(.notify) ||
               characteristic.properties.contains(.indicate)
    }

    public func connectToStoredDevice(_ uuid: String) -> Bool {
        guard let storedDevice = DeviceStorage.shared.getStoredDevice(uuid: uuid) else {
            return false
        }
        
        return DeviceConfiguration.openBLEDevice(
            name: storedDevice.name,
            deviceAddress: storedDevice.uuid
        )
    }

    public func clearRetrievalState() {
        logDebug("🧹 Clearing retrieval state")
        DispatchQueue.main.async { [weak self] in
            self?.isRetrievingLogs = false
            self?.currentRetrievalDevice = nil
        }
    }
}

extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}