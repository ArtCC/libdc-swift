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
    private var minLevel: LogLevel = .info
    public var shouldShowRawData = false  // Toggle for full hex dumps
    private var dataCounter = 0  // Track number of data packets
    private var totalBytesReceived = 0  // Track total bytes
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
    
    func setMinLevel(_ level: LogLevel) {
        minLevel = level
    }
    
    func log(_ message: String, level: LogLevel = .debug, file: String = #file, function: String = #function) {
        guard isEnabled && level.rawValue >= minLevel.rawValue else { return }
        
        let timestamp = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        
        // Special handling for BLE data logs
        if message.starts(with: "Received data") {
            handleBLEDataLog(message, timestamp)
            return
        }
        
        if message.contains("bytes, Buffer:") {
            // Skip buffer logs unless explicitly enabled
            if shouldShowRawData {
                let components = message.components(separatedBy: "Buffer: ")
                if components.count > 1 {
                    let hexData = components[1]
                    print("\(level.prefix) [\(timestamp)] 📦 Buffer: \(formatHexData(hexData))")
                }
            }
            return
        }
        
        print("\(level.prefix) [\(timestamp)] [\(fileName)] \(message)")
    }
    
    private func handleBLEDataLog(_ message: String, _ timestamp: String) {
        dataCounter += 1
        
        // Extract byte count from message
        if let bytesStart = message.range(of: "("),
           let bytesEnd = message.range(of: " bytes)") {
            let bytesStr = message[bytesStart.upperBound..<bytesEnd.lowerBound]
            if let bytes = Int(bytesStr) {
                totalBytesReceived += bytes
                
                // Print a summary every 5 packets or when exceeding certain thresholds
                if dataCounter % 5 == 0 {
                    print("📱 [\(timestamp)] BLE: Received \(dataCounter) packets (\(totalBytesReceived) bytes total)")
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