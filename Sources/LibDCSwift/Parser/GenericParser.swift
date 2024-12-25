import Foundation
import Clibdivecomputer

public enum ParserError: Error {
    case invalidParameters
    case parserCreationFailed(dc_status_t)
    case datetimeRetrievalFailed(dc_status_t)
    case sampleProcessingFailed(dc_status_t)
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
        
        func addCurrentPoint() {
            profile.append(ProfilePoint(
                time: currentTime,
                depth: currentDepth,
                temperature: currentTemperature,
                pressure: currentPressure
            ))
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
        
        // Process samples
        var sampleData = SampleData()
        
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
            maxDepth: sampleData.maxDepth,
            temperature: sampleData.lastTemperature,
            profile: sampleData.profile
        )
    }
} 