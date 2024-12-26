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
        let value = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<T>.size, alignment: MemoryLayout<T>.alignment)
        defer { value.deallocate() }
        
        let status = dc_parser_get_field(parser, type, flags, value)
        guard status == DC_STATUS_SUCCESS else { return nil }
        
        return value.load(as: T.self)
    }
    
    private class SampleDataWrapper {
        var data: SampleData
        
        init() {
            self.data = SampleData()
        }
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
        
        let wrapper = SampleDataWrapper()
        
        // Convert wrapper to UnsafeMutableRawPointer
        let wrapperPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(wrapper).toOpaque())
        
        let sampleCallback: dc_sample_callback_t = { type, valuePtr, userData in
            guard let userData = userData else { return }
            
            // Convert back from UnsafeMutableRawPointer to SampleDataWrapper
            let wrapper = Unmanaged<SampleDataWrapper>.fromOpaque(userData).takeUnretainedValue()
            guard let value = valuePtr?.pointee else { return }
            
            switch type {
            case DC_SAMPLE_TIME:
                wrapper.data.currentTime = TimeInterval(value.time) / 1000.0
                
            case DC_SAMPLE_DEPTH:
                wrapper.data.currentDepth = value.depth
                if value.depth > wrapper.data.maxDepth {
                    wrapper.data.maxDepth = value.depth
                }
                
            case DC_SAMPLE_TEMPERATURE:
                wrapper.data.currentTemperature = value.temperature
                wrapper.data.lastTemperature = value.temperature
                
            case DC_SAMPLE_PRESSURE:
                wrapper.data.currentPressure = value.pressure.value
                
            case DC_SAMPLE_EVENT:
                wrapper.data.addEvent(
                    type: parser_sample_event_t(value.event.type),
                    time: wrapper.data.currentTime,
                    value: value.event.value,
                    flags: value.event.flags
                )
                
            case DC_SAMPLE_DECO:
                // Decompression information
                if value.deco.type == DC_DECO_DECOSTOP.rawValue {
                    logInfo("Deco stop at \(value.deco.depth)m for \(value.deco.time) minutes")
                }
                
            case DC_SAMPLE_PPO2:
                // PPO2 readings from sensors
                let sensor = value.ppo2.sensor
                logInfo("PPO2 sensor \(sensor): \(value.ppo2.value) bar")
                
            case DC_SAMPLE_CNS:
                // CNS percentage
                logInfo("CNS: \(value.cns)%")
                
            case DC_SAMPLE_GASMIX:
                // Gas mix changes
                logInfo("Switched to gas mix \(value.gasmix)")
                
            default:
                break
            }
            
            if type == DC_SAMPLE_TIME {
                wrapper.data.addCurrentPoint()
            }
        }
        
        let samplesStatus = dc_parser_samples_foreach(parser, sampleCallback, wrapperPtr)
        
        // Release the wrapper after we're done
        Unmanaged<SampleDataWrapper>.fromOpaque(wrapperPtr).release()
        
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
            divetime: wrapper.data.divetime,
            maxDepth: wrapper.data.maxDepth,
            avgDepth: wrapper.data.avgDepth,
            atmospheric: wrapper.data.atmospheric,
            temperature: wrapper.data.lastTemperature,
            tempSurface: wrapper.data.tempSurface,
            tempMinimum: wrapper.data.tempMinimum,
            tempMaximum: wrapper.data.tempMaximum,
            diveMode: wrapper.data.diveMode,
            gasMixes: wrapper.data.gasMixes,
            tanks: wrapper.data.tanks,
            decoModel: wrapper.data.decoModel,
            location: wrapper.data.location,
            profile: wrapper.data.profile
        )
    }
} 