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
    
    public enum DownloadProgress: Equatable {
        case idle
        case inProgress(current: Int)
        case completed
        case error(String)
        case cancelled
        
        var description: String {
            switch self {
            case .idle:
                return "Ready"
            case .inProgress(let current):
                return "Downloading dive \(current)"
            case .completed:
                return "Completed"
            case .error(let message):
                return "Error: \(message)"
            case .cancelled:
                return "Cancelled"
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
            self.status = ""
            self.progress = .idle
        }
    }
    
    public func setDetailedError(_ message: String, status: dc_status_t? = nil) {
        let errorMessage = if let status = status {
            "\(message) (Status: \(status))"
        } else {
            message
        }
        DispatchQueue.main.async {
            self.progress = .error(errorMessage)
        }
    }
} 
