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

public struct GasMix {
    public let helium: Double
    public let oxygen: Double
    public let nitrogen: Double
    public let usage: dc_usage_t
    
    public init(helium: Double, oxygen: Double, nitrogen: Double, usage: dc_usage_t) {
        self.helium = helium
        self.oxygen = oxygen
        self.nitrogen = nitrogen
        self.usage = usage
    }
}

public struct TankInfo {
    public let gasMix: Int  // Index to gas mix
    public let type: dc_tankvolume_t
    public let volume: Double
    public let workPressure: Double
    public let beginPressure: Double
    public let endPressure: Double
    public let usage: dc_usage_t
    
    public init(gasMix: Int, type: dc_tankvolume_t, volume: Double, workPressure: Double, 
               beginPressure: Double, endPressure: Double, usage: dc_usage_t) {
        self.gasMix = gasMix
        self.type = type
        self.volume = volume
        self.workPressure = workPressure
        self.beginPressure = beginPressure
        self.endPressure = endPressure
        self.usage = usage
    }
}

public struct DecoModel {
    public let type: dc_decomodel_type_t
    public let conservatism: Int
    public let gfLow: UInt
    public let gfHigh: UInt
    
    public init(type: dc_decomodel_type_t, conservatism: Int, gfLow: UInt, gfHigh: UInt) {
        self.type = type
        self.conservatism = conservatism
        self.gfLow = gfLow
        self.gfHigh = gfHigh
    }
}

public struct Location {
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double
    
    public init(latitude: Double, longitude: Double, altitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
    }
}

public struct DiveData: Identifiable, Hashable {
    public let id = UUID()
    public let number: Int
    public let datetime: Date
    public let divetime: TimeInterval
    public let maxDepth: Double
    public let avgDepth: Double
    public let atmospheric: Double
    public let temperature: Double
    public let tempSurface: Double
    public let tempMinimum: Double
    public let tempMaximum: Double
    public let diveMode: dc_divemode_t
    public let gasMixes: [GasMix]
    public let tanks: [TankInfo]
    public let decoModel: DecoModel?
    public let location: Location?
    public let profile: [ProfilePoint]
    public let events: [DiveEvent]
    
    public var formattedDateTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: datetime)
    }
    
    public init(
        number: Int,
        datetime: Date,
        divetime: TimeInterval,
        maxDepth: Double,
        avgDepth: Double,
        atmospheric: Double,
        temperature: Double,
        tempSurface: Double,
        tempMinimum: Double,
        tempMaximum: Double,
        diveMode: dc_divemode_t,
        gasMixes: [GasMix] = [],
        tanks: [TankInfo] = [],
        decoModel: DecoModel? = nil,
        location: Location? = nil,
        profile: [ProfilePoint] = [],
        events: [DiveEvent] = []
    ) {
        self.number = number
        self.datetime = datetime
        self.divetime = divetime
        self.maxDepth = maxDepth
        self.avgDepth = avgDepth
        self.atmospheric = atmospheric
        self.temperature = temperature
        self.tempSurface = tempSurface
        self.tempMinimum = tempMinimum
        self.tempMaximum = tempMaximum
        self.diveMode = diveMode
        self.gasMixes = gasMixes
        self.tanks = tanks
        self.decoModel = decoModel
        self.location = location
        self.profile = profile
        self.events = events
    }
    
    public static func == (lhs: DiveData, rhs: DiveData) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
} 
