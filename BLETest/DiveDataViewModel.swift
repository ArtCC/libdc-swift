import Foundation
import Combine

class DiveDataViewModel: ObservableObject {
    @Published var dives: [DiveData] = []
    @Published var status: String = ""
    @Published var progress: DownloadProgress = .idle
    
    enum DownloadProgress {
        case idle
        case inProgress(current: Int, total: Int)
        case completed
        case error(String)
        
        var description: String {
            switch self {
            case .idle:
                return "Ready to download"
            case .inProgress(let current, let total):
                return "Downloading dive \(current) of \(total)"
            case .completed:
                return "Download completed"
            case .error(let message):
                return "Error: \(message)"
            }
        }
    }
    
    func addDive(number: Int, year: Int, month: Int, day: Int, 
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
            }
        }
    }
    
    func updateStatus(_ newStatus: String) {
        DispatchQueue.main.async {
            self.status = newStatus
        }
    }
    
    func updateProgress(current: Int, total: Int) {
        DispatchQueue.main.async {
            self.progress = .inProgress(current: current, total: total)
        }
    }
    
    func setError(_ message: String) {
        DispatchQueue.main.async {
            self.progress = .error(message)
        }
    }
    
    func clear() {
        DispatchQueue.main.async {
            self.dives.removeAll()
            self.status = ""
            self.progress = .idle
        }
    }
} 
