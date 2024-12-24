import Foundation

enum LogLevel: Int {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    
    var prefix: String {
        switch self {
        case .debug: return "🔍 DEBUG"
        case .info: return "ℹ️ INFO"
        case .warning: return "⚠️ WARN"
        case .error: return "❌ ERROR"
        }
    }
}

class Logger {
    static let shared = Logger()
    private var isEnabled = true
    private var minLevel: LogLevel = .debug
    public var shouldShowRawData = false  // Toggle for full hex dumps
    private var dataCounter = 0  // Track number of data packets
    private var totalBytesReceived = 0  // Track total bytes
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
    
    var minimumLogLevel: LogLevel {
        get { minLevel }
        set { minLevel = newValue }
    }
    
    func setMinLevel(_ level: LogLevel) {
        minLevel = level
    }
    
    func log(_ message: String, level: LogLevel = .debug, file: String = #file, function: String = #function) {
        guard isEnabled && level.rawValue >= minLevel.rawValue else { return }
        
        let timestamp = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        
        // Skip routine BLE data logs
        if message.starts(with: "Received data") {
            // Only handle if it's a completion or error message
            if message.contains("completed") || message.contains("error") {
                handleBLEDataLog(message, timestamp)
            }
            return
        }
        
        // Skip buffer logs unless explicitly requested and important
        if message.contains("bytes, Buffer:") {
            if shouldShowRawData && (message.contains("error") || message.contains("important")) {
                let components = message.components(separatedBy: "Buffer: ")
                if components.count > 1 {
                    let hexData = components[1]
                    print("\(level.prefix) [\(timestamp)] 📦 Buffer: \(formatHexData(hexData))")
                }
            }
            return
        }
        
        // Only log important BLE events
        if fileName == "BLEManager.swift" {
            let importantEvents = [
                "Bluetooth is powered on",
                "Successfully connected to",
                "Failed to connect",
                "Disconnected from",
                "Write characteristic found",
                "Notify characteristic found",
                "Notification state updated"
            ]
            
            if !importantEvents.contains(where: { message.contains($0) }) {
                return
            }
        }
        
        // Always show dive-related logs and errors
        if message.contains("🎯") || message.contains("📊") || message.contains("✅") || 
           message.contains("❌") || level == .error {
            print("\(level.prefix) [\(timestamp)] [\(fileName)] \(message)")
            return
        }
        
        // For other messages, only show info level and above by default
        if level.rawValue >= LogLevel.info.rawValue {
            print("\(level.prefix) [\(timestamp)] [\(fileName)] \(message)")
        }
    }
    
    private func handleBLEDataLog(_ message: String, _ timestamp: String) {
        dataCounter += 1
        
        // Extract byte count from message
        if let bytesStart = message.range(of: "("),
           let bytesEnd = message.range(of: " bytes)") {
            let bytesStr = message[bytesStart.upperBound..<bytesEnd.lowerBound]
            if let bytes = Int(bytesStr) {
                totalBytesReceived += bytes
                
                // Only print summary at the end or for significant events
                // Removed the periodic logging
                if message.contains("completed") || message.contains("error") {
                    print("📱 [\(timestamp)] BLE: Total received: \(totalBytesReceived) bytes in \(dataCounter) packets")
                }
            }
        }
    }
    
    private func formatHexData(_ hexString: String) -> String {
        // Format hex data in chunks of 8 bytes (16 characters)
        var formatted = ""
        var index = hexString.startIndex
        let chunkSize = 16
        
        while index < hexString.endIndex {
            let endIndex = hexString.index(index, offsetBy: chunkSize, limitedBy: hexString.endIndex) ?? hexString.endIndex
            let chunk = hexString[index..<endIndex]
            formatted += chunk
            if endIndex != hexString.endIndex {
                formatted += "\n\t\t\t"  // Indent continuation lines
            }
            index = endIndex
        }
        
        return formatted
    }
    
    func setShowRawData(_ show: Bool) {
        shouldShowRawData = show
    }
    
    func resetDataCounters() {
        dataCounter = 0
        totalBytesReceived = 0
    }
}

// Global convenience functions
func logDebug(_ message: String, file: String = #file, function: String = #function) {
    Logger.shared.log(message, level: .debug, file: file, function: function)
}

func logInfo(_ message: String, file: String = #file, function: String = #function) {
    Logger.shared.log(message, level: .info, file: file, function: function)
}

func logWarning(_ message: String, file: String = #file, function: String = #function) {
    Logger.shared.log(message, level: .warning, file: file, function: function)
}

func logError(_ message: String, file: String = #file, function: String = #function) {
    Logger.shared.log(message, level: .error, file: file, function: function)
} 