//import Foundation
//
//struct DiveData: Identifiable {
//    let id = UUID()
//    let date: Date
//    let diveTime: TimeInterval
//    let maxDepth: Double
//    
//    init(cDiveData: dive_data_t) {
//        var components = DateComponents()
//        components.year = Int(cDiveData.year)
//        components.month = Int(cDiveData.month)
//        components.day = Int(cDiveData.day)
//        components.hour = Int(cDiveData.hour)
//        components.minute = Int(cDiveData.minute)
//        components.second = Int(cDiveData.second)
//        
//        self.date = Calendar.current.date(from: components) ?? Date()
//        self.diveTime = TimeInterval(cDiveData.divetime)
//        self.maxDepth = cDiveData.maxdepth
//    }
//} 
