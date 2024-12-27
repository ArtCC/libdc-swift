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
    private static func getField<T>(_ parser: OpaquePointer?, type: dc_field_type_t, flags: UInt32 = 0) -> T? {
        let value = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<T>.size, alignment: MemoryLayout<T>.alignment)
        defer { value.deallocate() }
        
        let status = dc_parser_get_field(parser, type, flags, value)
        guard status == DC_STATUS_SUCCESS else { return nil }
        
        return value.load(as: T.self)
    }
    
    private class SampleDataWrapper {
        var data = SampleData()
        
        func addProfilePoint() {
            let point = DiveProfilePoint(
                time: data.time,
                depth: data.depth,
                temperature: data.temperature,
                pressure: data.pressure.last?.value
            )
            data.profile.append(point)
            
            // Track temperature ranges
            if let temp = data.temperature {
                data.tempMinimum = min(data.tempMinimum, temp)
                data.tempMaximum = max(data.tempMaximum, temp)
                data.lastTemperature = temp
                // Store surface temperature if not set
                if data.tempSurface == 0 {
                    data.tempSurface = temp
                }
            }
        }
        
        func addTank(_ tank: dc_tank_t) {
            data.tanks.append(GenericParser.convertTank(tank))
        }
        
        func setDecoModel(_ model: dc_decomodel_t) {
            data.decoModel = GenericParser.convertDecoModel(model)
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
        logInfo("Creating parser for family: \(family), model: \(model), size: \(dataSize)")
        
        var parser: OpaquePointer?
        var rc: dc_status_t
        
        // Create parser based on device family
        switch family {
        case .suuntoEonSteel:
            logInfo("Using Suunto EON Steel parser")
            rc = suunto_eonsteel_parser_create(&parser, context, diveData, dataSize, 0)
        case .shearwaterPetrel:
            logInfo("Using Shearwater Petrel parser")
            rc = shearwater_petrel_parser_create(&parser, context, diveData, dataSize)
        case .shearwaterPredator:
            logInfo("Using Shearwater Predator parser")
            rc = shearwater_predator_parser_create(&parser, context, diveData, dataSize)
        }
        
        guard rc == DC_STATUS_SUCCESS, parser != nil else {
            logError("❌ Parser creation failed with status: \(rc)")
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
            guard let userData = userData,
                  let value = valuePtr?.pointee else { return }
            
            let wrapper = Unmanaged<SampleDataWrapper>.fromOpaque(userData).takeUnretainedValue()
            
            switch type {
            case DC_SAMPLE_TIME:
                wrapper.data.time = TimeInterval(value.time) / 1000.0
                wrapper.addProfilePoint()
                
            case DC_SAMPLE_DEPTH:
                wrapper.data.depth = value.depth
                wrapper.data.maxDepth = max(wrapper.data.maxDepth, value.depth)
                
            case DC_SAMPLE_PRESSURE:
                wrapper.data.pressure.append((
                    tank: Int(value.pressure.tank),
                    value: value.pressure.value
                ))
                
            case DC_SAMPLE_TEMPERATURE:
                wrapper.data.temperature = value.temperature
                
            case DC_SAMPLE_EVENT:
                wrapper.data.event = SampleData.Event(
                    type: parser_sample_event_t(value.event.type),
                    value: value.event.value,
                    flags: value.event.flags
                )
                
            case DC_SAMPLE_RBT:
                wrapper.data.rbt = value.rbt
                
            case DC_SAMPLE_HEARTBEAT:
                wrapper.data.heartbeat = value.heartbeat
                
            case DC_SAMPLE_BEARING:
                wrapper.data.bearing = value.bearing
                
            case DC_SAMPLE_SETPOINT:
                wrapper.data.setpoint = value.setpoint
                
            case DC_SAMPLE_PPO2:
                wrapper.data.ppo2.append((
                    sensor: value.ppo2.sensor,
                    value: value.ppo2.value
                ))
                
            case DC_SAMPLE_CNS:
                wrapper.data.cns = value.cns * 100.0  // Convert to percentage
                
            case DC_SAMPLE_DECO:
                wrapper.data.deco = SampleData.DecoData(
                    type: dc_deco_type_t(rawValue: value.deco.type),
                    depth: value.deco.depth,
                    time: value.deco.time,
                    tts: value.deco.tts
                )
                
            case DC_SAMPLE_GASMIX:
                wrapper.data.gasmix = Int(value.gasmix)
                
            default:
                break
            }
        }
        
        let samplesStatus = dc_parser_samples_foreach(parser, sampleCallback, wrapperPtr)
        
        // Release the wrapper after we're done
        Unmanaged<SampleDataWrapper>.fromOpaque(wrapperPtr).release()
        
        guard samplesStatus == DC_STATUS_SUCCESS else {
            throw ParserError.sampleProcessingFailed(samplesStatus)
        }
        
        // Get tank information
        if let tankCount: UInt32 = getField(parser, type: DC_FIELD_TANK_COUNT) {
            for i in 0..<tankCount {
                if var tank: dc_tank_t = getField(parser, type: DC_FIELD_TANK, flags: UInt32(i)) {
                    wrapper.addTank(tank)
                }
            }
        }
        
        // Get deco model
        if var decoModel: dc_decomodel_t = getField(parser, type: DC_FIELD_DECOMODEL) {
            wrapper.setDecoModel(decoModel)
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
            maxDepth: wrapper.data.maxDepth,
            divetime: wrapper.data.divetime,
            temperature: wrapper.data.lastTemperature,
            profile: wrapper.data.profile,
            tankPressure: wrapper.data.pressure.map { $0.value },
            gasMix: wrapper.data.gasmix,
            gasMixCount: wrapper.data.gasMixes.count,
            salinity: wrapper.data.salinity,
            atmospheric: wrapper.data.atmospheric,
            surfaceTemperature: wrapper.data.tempSurface,
            minTemperature: wrapper.data.tempMinimum,
            maxTemperature: wrapper.data.tempMaximum,
            tankCount: wrapper.data.tanks.count,
            tanks: wrapper.data.tanks,
            diveMode: wrapper.data.diveMode,
            decoModel: wrapper.data.decoModel,
            location: wrapper.data.location,
            rbt: wrapper.data.rbt,
            heartbeat: wrapper.data.heartbeat,
            bearing: wrapper.data.bearing,
            setpoint: wrapper.data.setpoint,
            ppo2Readings: wrapper.data.ppo2,
            cns: wrapper.data.cns,
            decoStop: wrapper.data.deco.map { deco in
                DiveData.DecoStop(
                    depth: deco.depth,
                    time: TimeInterval(deco.time),
                    type: Int(deco.type.rawValue)
                )
            }
        )
    }
    
    private static func convertTank(_ tank: dc_tank_t) -> DiveData.Tank {
        return DiveData.Tank(
            volume: tank.volume,
            workingPressure: tank.workpressure,
            beginPressure: tank.beginpressure,
            endPressure: tank.endpressure,
            gasMix: Int(tank.gasmix),
            usage: convertUsage(tank.usage)
        )
    }
    
    private static func convertUsage(_ usage: dc_usage_t) -> DiveData.Tank.Usage {
        switch usage {
        case DC_USAGE_NONE:
            return .none
        case DC_USAGE_OXYGEN:
            return .oxygen
        case DC_USAGE_DILUENT:
            return .diluent
        case DC_USAGE_SIDEMOUNT:
            return .sidemount
        default:
            return .none
        }
    }
    
    private static func convertDecoModel(_ model: dc_decomodel_t) -> DiveData.DecoModel {
        let type: DiveData.DecoModel.DecoType
        switch model.type {
        case DC_DECOMODEL_BUHLMANN:
            type = .buhlmann
        case DC_DECOMODEL_VPM:
            type = .vpm
        case DC_DECOMODEL_RGBM:
            type = .rgbm
        case DC_DECOMODEL_DCIEM:
            type = .dciem
        default:
            type = .none
        }
        
        return DiveData.DecoModel(
            type: type,
            conservatism: Int(model.conservatism),
            gfLow: model.params.gf.low,
            gfHigh: model.params.gf.high
        )
    }
} 