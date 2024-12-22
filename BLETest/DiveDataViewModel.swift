//import Foundation
//import Combine
//
//class DiveDataViewModel: ObservableObject {
//    @Published var dives: [DiveData] = []
//    private var cancellables = Set<AnyCancellable>()
//    
//    init() {
//        // Listen for dive data updates
//        NotificationCenter.default.publisher(for: Notification.Name("DiveDataUpdated"))
//            .sink { [weak self] _ in
//                self?.updateDiveData()
//            }
//            .store(in: &cancellables)
//    }
//    
//    func updateDiveData() {
//        let count = get_dive_count()
//        var newDives: [DiveData] = []
//        
//        for i in 0..<count {
//            if let diveDataPtr = get_dive_data(Int32(i)) {
//                let diveData = diveDataPtr.pointee
//                newDives.append(DiveData(cDiveData: diveData))
//            }
//        }
//        
//        DispatchQueue.main.async {
//            self.dives = newDives
//        }
//    }
//    
//    func clearDiveData() {
//        reset_dive_data()
//        dives = []
//    }
//} 
