import Foundation

public struct DiveSample {
    public let datetime: Date
    public let maxDepth: Double
    public let temperature: Double
    
    public init(
        datetime: Date,
        maxDepth: Double,
        temperature: Double
    ) {
        self.datetime = datetime
        self.maxDepth = maxDepth
        self.temperature = temperature
    }
} 