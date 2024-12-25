import Foundation

public struct ProfilePoint {
    public let time: TimeInterval  // seconds from dive start
    public let depth: Double
    public let temperature: Double?
    public let pressure: Double?
    
    public init(time: TimeInterval, depth: Double, temperature: Double? = nil, pressure: Double? = nil) {
        self.time = time
        self.depth = depth
        self.temperature = temperature
        self.pressure = pressure
    }
}

public struct DiveData: Identifiable, Hashable {
    public let id = UUID()
    public let number: Int
    public let datetime: Date
    public let maxDepth: Double
    public let temperature: Double
    public let profile: [ProfilePoint]
    
    public var formattedDateTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: datetime)
    }
    
    public init(
        number: Int,
        datetime: Date,
        maxDepth: Double,
        temperature: Double,
        profile: [ProfilePoint] = []
    ) {
        self.number = number
        self.datetime = datetime
        self.maxDepth = maxDepth
        self.temperature = temperature
        self.profile = profile
    }
    
    public static func == (lhs: DiveData, rhs: DiveData) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
} 
