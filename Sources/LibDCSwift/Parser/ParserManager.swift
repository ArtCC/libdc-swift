import Foundation
import Clibdivecomputer
import LibDCBridge

public class ParserManager {
    public static func createParser(
        data: Data,
        context: UnsafeMutablePointer<dc_context_t>?,
        family: DeviceConfiguration.DeviceFamily,
        model: UInt32
    ) -> UnsafeMutablePointer<dc_parser_t?>? {
        var parser: UnsafeMutablePointer<dc_parser_t?>?
        var descriptor: UnsafeMutablePointer<dc_descriptor_t>?
        
        // Get descriptor for the device
        var iterator: UnsafeMutablePointer<dc_iterator_t>?
        guard dc_descriptor_iterator(&iterator) == DC_STATUS_SUCCESS else {
            return nil
        }
        defer { dc_iterator_free(iterator) }
        
        // Find matching descriptor
        while dc_iterator_next(iterator, &descriptor) == DC_STATUS_SUCCESS {
            if dc_descriptor_get_type(descriptor) == family.asDCFamily &&
               dc_descriptor_get_model(descriptor) == model {
                break
            }
            dc_descriptor_free(descriptor)
            descriptor = nil
        }
        
        guard let descriptor = descriptor else {
            return nil
        }
        defer { dc_descriptor_free(descriptor) }
        
        // Create parser
        let status = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> dc_status_t in
            return dc_parser_new2(
                &parser,
                context,
                descriptor,
                bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                data.count
            )
        }
        
        return status == DC_STATUS_SUCCESS ? parser : nil
    }
} 
