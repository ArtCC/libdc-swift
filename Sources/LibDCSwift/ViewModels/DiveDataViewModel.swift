import Foundation
import Combine

public class DiveDataViewModel: ObservableObject {
    @Published public var dives: [DiveData] = []
    @Published public var status: String = ""
    @Published public var progress: DownloadProgress = .idle
    @Published public var lastFingerprint: Data?
    private let fingerprintKey = "lastDiveFingerprint"
    
    public init() {
        if let savedFingerprint = UserDefaults.standard.data(forKey: fingerprintKey) {
            self.lastFingerprint = savedFingerprint
        }
    }
    
    public func saveFingerprint(_ fingerprint: Data) {
        self.lastFingerprint = fingerprint
        UserDefaults.standard.set(fingerprint, forKey: fingerprintKey)
    }
    
    public enum DownloadProgress {
        case idle
        case inProgress(count: Int)
        case completed
        case error(String)
        
        public var description: String {
            switch self {
            case .idle:
                return "Ready to download"
            case .inProgress(let count):
                return "Downloading dive \(max(1,count))"
            case .completed:
                return "Download completed"
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
            let dive = DiveData(number: number,
                              datetime: date,
                              maxDepth: maxDepth,
                              temperature: temperature)
            DispatchQueue.main.async {
                self.dives.append(dive)
                if case .inProgress = self.progress {
                    self.progress = .inProgress(count: self.dives.count)
                }
            }
        }
    }
    
    public func updateStatus(_ newStatus: String) {
        DispatchQueue.main.async {
            self.status = newStatus
        }
    }
    
    public func updateProgress(current: Int, total: Int?) {
        DispatchQueue.main.async {
            self.progress = .inProgress(count: max(1,current))
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
    
    public func clearFingerprint() {
        self.lastFingerprint = nil
        UserDefaults.standard.removeObject(forKey: fingerprintKey)
        objectWillChange.send()
    }
} 
