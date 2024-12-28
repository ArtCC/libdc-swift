import Foundation
import Combine

public class DiveDataViewModel: ObservableObject {
    @Published public var dives: [DiveData] = []
    @Published public var status: String = ""
    @Published public var progress: DownloadProgress = .idle
    @Published public var lastFingerprint: Data?
    private let fingerprintKey = "lastDiveFingerprint"
    
    public init() {
        loadFingerprint()
    }
    
    private func loadFingerprint() {
        if let savedFingerprint = UserDefaults.standard.data(forKey: fingerprintKey) {
            DispatchQueue.main.async {
                self.lastFingerprint = savedFingerprint
            }
        }
    }
    
    public func saveFingerprint(_ fingerprint: Data) {
        DispatchQueue.main.async {
            self.lastFingerprint = fingerprint
            UserDefaults.standard.set(fingerprint, forKey: self.fingerprintKey)
        }
    }
    
    public func clearFingerprint() {
        DispatchQueue.main.async {
            self.lastFingerprint = nil
            UserDefaults.standard.removeObject(forKey: self.fingerprintKey)
            self.objectWillChange.send()
        }
    }
    
    public enum DownloadProgress: CustomStringConvertible {
        case idle
        case inProgress(current: Int)
        case completed
        case cancelled
        case error(String)
        
        public var description: String {
            switch self {
            case .idle:
                return "Ready"
            case .inProgress:
                return ""
            case .completed:
                return "Completed"
            case .cancelled:
                return "Cancelled"
            case .error(let message):
                return "Error: \(message)"
            }
        }
    }
    
    public func addDive(number: Int, year: Int, month: Int, day: Int, 
                       hour: Int, minute: Int, second: Int,
                       maxDepth: Double, temperature: Double) {
        let components = DateComponents(year: year, month: month, day: day,
                                     hour: hour, minute: minute, second: second)
        if let date = Calendar.current.date(from: components) {
            let dive = DiveData(
                number: number,
                datetime: date,
                maxDepth: maxDepth,
                divetime: 0,
                temperature: temperature,
                profile: [],
                tankPressure: [],
                gasMix: nil,
                gasMixCount: nil,
                salinity: nil,
                atmospheric: 1.0,
                surfaceTemperature: nil,
                minTemperature: nil,
                maxTemperature: nil,
                tankCount: nil,
                tanks: nil,
                diveMode: .openCircuit,
                decoModel: nil,
                location: nil,
                rbt: nil,
                heartbeat: nil,
                bearing: nil,
                setpoint: nil,
                ppo2Readings: [],
                cns: nil,
                decoStop: nil
            )
            DispatchQueue.main.async {
                self.dives.append(dive)
                if case .inProgress = self.progress {
                    self.progress = .inProgress(current: self.dives.count)
                }
            }
        }
    }
    
    public func updateStatus(_ newStatus: String) {
        DispatchQueue.main.async {
            self.status = newStatus
        }
    }
    
    public func updateProgress(current: Int) {
        DispatchQueue.main.async {
            self.status = "Downloading dive \(current)"
            self.progress = .inProgress(current: current)
        }
    }
    
    public func setError(_ message: String) {
        DispatchQueue.main.async {
            self.progress = .error(message)
        }
    }
    
    public func clear() {
        DispatchQueue.main.async {
            self.dives.removeAll()
            if case .idle = self.progress {
                self.status = ""
            }
            self.progress = .idle
        }
    }
    
    public func setDetailedError(_ message: String, status: dc_status_t) {
        DispatchQueue.main.async {
            let statusDescription = switch status {
            case DC_STATUS_SUCCESS: "Success"
            case DC_STATUS_DONE: "Done"
            case DC_STATUS_UNSUPPORTED: "Unsupported Operation"
            case DC_STATUS_INVALIDARGS: "Invalid Arguments"
            case DC_STATUS_NOMEMORY: "Out of Memory"
            case DC_STATUS_NODEVICE: "No Device"
            case DC_STATUS_NOACCESS: "No Access"
            case DC_STATUS_IO: "Communication Error"
            case DC_STATUS_TIMEOUT: "Timeout"
            case DC_STATUS_PROTOCOL: "Protocol Error"
            case DC_STATUS_DATAFORMAT: "Data Format Error"
            case DC_STATUS_CANCELLED: "Cancelled"
            default: "Unknown Error (\(status))"
            }
            
            self.progress = .error("\(message): \(statusDescription)")
        }
    }
} 
