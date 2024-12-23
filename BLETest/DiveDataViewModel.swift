import Foundation
import Combine

class DiveDataViewModel: ObservableObject {
    @Published var dives: [DiveData] = []
    @Published var status: String = ""
    
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
    
    func clear() {
        DispatchQueue.main.async {
            self.dives.removeAll()
            self.status = ""
        }
    }
} 
