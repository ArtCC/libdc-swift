import Foundation
import Clibdivecomputer

/*
 Generic Dive Computer Parser
 
 This parser collects comprehensive dive data from various dive computers:
 
 Basic Dive Info:
 - Dive Time: Total duration of the dive in seconds
 - Max Depth: Maximum depth reached during dive (meters)
 - Avg Depth: Average depth throughout dive (meters)
 - Atmospheric: Surface pressure (bar)
 
 Temperature Data:
 - Surface Temperature: Temperature at start of dive (Celsius)
 - Minimum Temperature: Lowest temperature during dive
 - Maximum Temperature: Highest temperature during dive
 
 Gas & Tank Information:
 - Gas Mixes: List of all gas mixes used
   * Oxygen percentage (O2)
   * Helium percentage (He)
   * Nitrogen percentage (N2)
   * Usage type (oxygen, diluent, sidemount)
 - Tank Data:
   * Volume (liters)
   * Working pressure (bar)
   * Start/End pressures
   * Associated gas mix
 
 Decompression Info:
 - Decompression Model (Bühlmann, VPM, RGBM, etc.)
 - Conservatism settings
 - Gradient Factors (low/high) for Bühlmann
 
 Location:
 - GPS coordinates (if supported)
 - Altitude of dive site
 
 Detailed Profile:
 Time series data including:
 - Depth readings
 - Temperature
 - Tank pressures
 - Events:
   * Gas switches
   * Deco/Safety stops
   * Ascent rate warnings
   * Violations
   * PPO2 warnings
   * User-set bookmarks
 
 Sample Events Legend:
 - DECOSTOP: Required decompression stop
 - ASCENT: Ascent rate warning
 - CEILING: Ceiling violation
 - WORKLOAD: Work load indication
 - TRANSMITTER: Transmitter status/warnings
 - VIOLATION: Generic violation
 - BOOKMARK: User-marked point
 - SURFACE: Surface event
 - SAFETYSTOP: Safety stop (voluntary/mandatory)
 - GASCHANGE: Gas mix switch
 - DEEPSTOP: Deep stop
 - CEILING_SAFETYSTOP: Ceiling during safety stop
 - FLOOR: Floor reached during dive
 - DIVETIME: Dive time notification
 - MAXDEPTH: Max depth reached
 - OLF: Oxygen limit fraction
 - PO2: PPO2 warning
 - AIRTIME: Remaining air time warning
 - RGBM: RGBM warning
 - HEADING: Compass heading
 - TISSUELEVEL: Tissue saturation
*/

public enum ParserError: Error {
    case invalidParameters
    case parserCreationFailed(dc_status_t)
    case datetimeRetrievalFailed(dc_status_t)
    case sampleProcessingFailed(dc_status_t)
}

public struct DiveEvent {
    public let type: parser_sample_event_t
    public let time: TimeInterval
    public let value: UInt32
    public let flags: UInt32
    
    public var description: String {
        switch type {
        case SAMPLE_EVENT_GASCHANGE:
            return "Gas mix changed to \(value)"
        case SAMPLE_EVENT_VIOLATION:
            return "Violation occurred"
        case SAMPLE_EVENT_BOOKMARK:
            return "User bookmark"
        case SAMPLE_EVENT_ASCENT:
            return "Ascent rate warning"
        case SAMPLE_EVENT_DECOSTOP:
            return "Deco stop required"
        case SAMPLE_EVENT_CEILING:
            return "Ceiling violation"
        case SAMPLE_EVENT_SAFETYSTOP:
            return "Safety stop"
        case SAMPLE_EVENT_DEEPSTOP:
            return "Deep stop"
        case SAMPLE_EVENT_PO2:
            return "PPO2 warning"
        default:
            return "Event type: \(type.rawValue)"
        }
    }
}

public class GenericParser {
    private class SampleData {
        var maxDepth: Double = 0.0
        var lastTemperature: Double = 0.0
        var profile: [ProfilePoint] = []
        var currentTime: TimeInterval = 0
        var currentDepth: Double = 0
        var currentTemperature: Double?
        var currentPressure: Double?
        
        // Additional dive information
        var divetime: TimeInterval = 0
        var avgDepth: Double = 0
        var atmospheric: Double = 0
        var tempSurface: Double = 0
        var tempMinimum: Double = Double.infinity
        var tempMaximum: Double = -Double.infinity
        var diveMode: dc_divemode_t = DC_DIVEMODE_OC
        var gasMixes: [GasMix] = []
        var tanks: [TankInfo] = []
        var decoModel: DecoModel?
        var location: Location?
        
        // Add events array
        var events: [DiveEvent] = []
        
        func addCurrentPoint() {
            profile.append(ProfilePoint(
                time: currentTime,
                depth: currentDepth,
                temperature: currentTemperature,
                pressure: currentPressure
            ))
        }
        
        func addEvent(type: parser_sample_event_t, time: TimeInterval, value: UInt32, flags: UInt32) {
            events.append(DiveEvent(type: type, time: time, value: value, flags: flags))
        }
    }
    
    private static func getField<T>(_ parser: OpaquePointer?, type: dc_field_type_t, flags: UInt32 = 0) -> T? {
        var value = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<T>.size, alignment: MemoryLayout<T>.alignment)
        defer { value.deallocate() }
        
        let status = dc_parser_get_field(parser, type, flags, value)
        guard status == DC_STATUS_SUCCESS else { return nil }
        
        return value.load(as: T.self)
    }
    
    public static func parseDiveData(
        family: DeviceConfiguration.DeviceFamily,
        model: UInt32,
        diveNumber: Int,
        diveData: UnsafePointer<UInt8>,
        dataSize: Int,
        context: OpaquePointer? = nil
    ) throws -> DiveData {
        var parser: OpaquePointer?
        var rc: dc_status_t
        
        // Create parser based on device family
        switch family {
        case .suuntoEonSteel:
            rc = suunto_eonsteel_parser_create(&parser, context, diveData, dataSize, 0)
        case .shearwaterPetrel:
            rc = shearwater_petrel_parser_create(&parser, context, diveData, dataSize)
        case .shearwaterPredator:
            rc = shearwater_predator_parser_create(&parser, context, diveData, dataSize)
        }
        
        guard rc == DC_STATUS_SUCCESS, parser != nil else {
            throw ParserError.parserCreationFailed(rc)
        }
        
        defer {
            dc_parser_destroy(parser)
        }
        
        // Get dive time
        var datetime = dc_datetime_t()
        let datetimeStatus = dc_parser_get_datetime(parser, &datetime)
        
        guard datetimeStatus == DC_STATUS_SUCCESS else {
            throw ParserError.datetimeRetrievalFailed(datetimeStatus)
        }
        
        // Process samples and collect additional data
        var sampleData = SampleData()
        
        // Get dive time
        if let divetime: UInt32 = getField(parser, type: DC_FIELD_DIVETIME) {
            sampleData.divetime = TimeInterval(divetime)
        }
        
        // Get average depth
        if let avgDepth: Double = getField(parser, type: DC_FIELD_AVGDEPTH) {
            sampleData.avgDepth = avgDepth
        }
        
        // Get atmospheric pressure
        if let atmospheric: Double = getField(parser, type: DC_FIELD_ATMOSPHERIC) {
            sampleData.atmospheric = atmospheric
        }
        
        // Get temperature data
        if let tempSurface: Double = getField(parser, type: DC_FIELD_TEMPERATURE_SURFACE) {
            sampleData.tempSurface = tempSurface
        }
        if let tempMin: Double = getField(parser, type: DC_FIELD_TEMPERATURE_MINIMUM) {
            sampleData.tempMinimum = tempMin
        }
        if let tempMax: Double = getField(parser, type: DC_FIELD_TEMPERATURE_MAXIMUM) {
            sampleData.tempMaximum = tempMax
        }
        
        // Get dive mode
        if let diveMode: dc_divemode_t = getField(parser, type: DC_FIELD_DIVEMODE) {
            sampleData.diveMode = diveMode
        }
        
        // Get gas mixes
        if let gasMixCount: UInt32 = getField(parser, type: DC_FIELD_GASMIX_COUNT) {
            for i in 0..<gasMixCount {
                if var gasMix: dc_gasmix_t = getField(parser, type: DC_FIELD_GASMIX, flags: UInt32(i)) {
                    sampleData.gasMixes.append(GasMix(
                        helium: gasMix.helium,
                        oxygen: gasMix.oxygen,
                        nitrogen: gasMix.nitrogen,
                        usage: gasMix.usage
                    ))
                }
            }
        }
        
        // Get tank info
        if let tankCount: UInt32 = getField(parser, type: DC_FIELD_TANK_COUNT) {
            for i in 0..<tankCount {
                if var tank: dc_tank_t = getField(parser, type: DC_FIELD_TANK, flags: UInt32(i)) {
                    sampleData.tanks.append(TankInfo(
                        gasMix: Int(tank.gasmix),
                        type: tank.type,
                        volume: tank.volume,
                        workPressure: tank.workpressure,
                        beginPressure: tank.beginpressure,
                        endPressure: tank.endpressure,
                        usage: tank.usage
                    ))
                }
            }
        }
        
        // Get deco model
        if var decoModel: dc_decomodel_t = getField(parser, type: DC_FIELD_DECOMODEL) {
            sampleData.decoModel = DecoModel(
                type: decoModel.type,
                conservatism: decoModel.conservatism,
                gfLow: decoModel.params.gf.low,
                gfHigh: decoModel.params.gf.high
            )
        }
        
        // Get location
        if var location: dc_location_t = getField(parser, type: DC_FIELD_LOCATION) {
            sampleData.location = Location(
                latitude: location.latitude,
                longitude: location.longitude,
                altitude: location.altitude
            )
        }
        
        // Process samples
        let sampleCallback: dc_sample_callback_t = { type, valuePtr, userData in
            guard let sampleDataPtr = userData?.assumingMemoryBound(to: SampleData.self),
                  let value = valuePtr?.pointee else {
                return
            }
            
            switch type {
            case DC_SAMPLE_TIME:
                sampleDataPtr.pointee.currentTime = TimeInterval(value.time) / 1000.0 // Convert ms to seconds
                
            case DC_SAMPLE_DEPTH:
                sampleDataPtr.pointee.currentDepth = value.depth
                if value.depth > sampleDataPtr.pointee.maxDepth {
                    sampleDataPtr.pointee.maxDepth = value.depth
                }
                
            case DC_SAMPLE_TEMPERATURE:
                sampleDataPtr.pointee.currentTemperature = value.temperature
                sampleDataPtr.pointee.lastTemperature = value.temperature
                
            case DC_SAMPLE_PRESSURE:
                sampleDataPtr.pointee.currentPressure = value.pressure.value
                
            case DC_SAMPLE_EVENT:
                sampleDataPtr.pointee.addEvent(
                    type: parser_sample_event_t(value.event.type),
                    time: sampleDataPtr.pointee.currentTime,
                    value: value.event.value,
                    flags: value.event.flags
                )
                
            case DC_SAMPLE_DECO:
                // Decompression information
                if value.deco.type == DC_DECO_DECOSTOP {
                    logInfo("Deco stop at \(value.deco.depth)m for \(value.deco.time) minutes")
                }
                
            case DC_SAMPLE_PPO2:
                // PPO2 readings from sensors
                if let sensor = value.ppo2.sensor {
                    logInfo("PPO2 sensor \(sensor): \(value.ppo2.value) bar")
                }
                
            case DC_SAMPLE_CNS:
                // CNS percentage
                logInfo("CNS: \(value.cns)%")
                
            case DC_SAMPLE_GASMIX:
                // Gas mix changes
                logInfo("Switched to gas mix \(value.gasmix)")
                
            default:
                break
            }
            
            // Add point to profile after processing each time sample
            if type == DC_SAMPLE_TIME {
                sampleDataPtr.pointee.addCurrentPoint()
            }
        }
        
        let samplesStatus = dc_parser_samples_foreach(parser, sampleCallback, &sampleData)
        
        guard samplesStatus == DC_STATUS_SUCCESS else {
            throw ParserError.sampleProcessingFailed(samplesStatus)
        }
        
        // Create date from components
        var dateComponents = DateComponents()
        dateComponents.year = Int(datetime.year)
        dateComponents.month = Int(datetime.month)
        dateComponents.day = Int(datetime.day)
        dateComponents.hour = Int(datetime.hour)
        dateComponents.minute = Int(datetime.minute)
        dateComponents.second = Int(datetime.second)
        
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: dateComponents) else {
            throw ParserError.invalidParameters
        }
        
        return DiveData(
            number: diveNumber,
            datetime: date,
            divetime: sampleData.divetime,
            maxDepth: sampleData.maxDepth,
            avgDepth: sampleData.avgDepth,
            atmospheric: sampleData.atmospheric,
            temperature: sampleData.lastTemperature,
            tempSurface: sampleData.tempSurface,
            tempMinimum: sampleData.tempMinimum,
            tempMaximum: sampleData.tempMaximum,
            diveMode: sampleData.diveMode,
            gasMixes: sampleData.gasMixes,
            tanks: sampleData.tanks,
            decoModel: sampleData.decoModel,
            location: sampleData.location,
            profile: sampleData.profile
        )
    }
} 