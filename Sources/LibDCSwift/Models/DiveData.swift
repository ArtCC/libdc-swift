import Foundation

public struct DiveData: Identifiable, Hashable {
    public let id = UUID()
    public let number: Int
    public let datetime: Date
    public let maxDepth: Double
    public let temperature: Double
    
    public var formattedDateTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: datetime)
    }
    
    public init(number: Int, datetime: Date, maxDepth: Double, temperature: Double) {
        self.number = number
        self.datetime = datetime
        self.maxDepth = maxDepth
        self.temperature = temperature
    }
} 
