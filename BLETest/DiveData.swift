import Foundation

struct DiveData: Identifiable, Hashable {
    let id = UUID()
    let number: Int
    let datetime: Date
    let maxDepth: Double
    let temperature: Double
    
    var formattedDateTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: datetime)
    }
} 
