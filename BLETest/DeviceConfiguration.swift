import Foundation

@objc public class DeviceConfiguration: NSObject {
    @objc public static func openSuuntoEonSteel(deviceAddress: String) -> Bool {
        var deviceData = device_data_t()
        let status = open_suunto_eonsteel(&deviceData, deviceAddress.cString(using: .utf8))
        return status == DC_STATUS_SUCCESS
    }
}
