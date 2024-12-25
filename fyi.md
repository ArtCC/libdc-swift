# BLE Test Application Overview

This codebase implements a Bluetooth Low Energy (BLE) application for communicating with Suunto EON Steel and D5 dive computers.

## Key Files and Their Purposes

### Core Components
- **BLEManager.swift**: Handles BLE communication and device management, now with dynamic service discovery.
- **BluetoothScanView.swift**: Main UI for scanning and connecting to devices.
- **ConnectedDeviceView.swift**: Handles dive log retrieval and display.
- **DiveDataViewModel.swift**: Manages dive data and state.

### Protocol Implementation
- **configuredc.c**: Bridge between Swift and libdivecomputer.
- **suunto_eonsteel.c**: Suunto-specific protocol implementation.

## Key Features

### HDLC Protocol
- Frame Start/End: 0x7E marker
- Data is escaped to avoid conflicts
- Example frame: 7E [payload] 7E

### Dive Log Structure
- Directory listing returns .LOG files (one per dive)
- Each log contains timestamp and SBEM data
- Sample data includes depth, temperature, pressure

### Event Handling
- Uses dc_device_set_events() for device updates
- Handles device info, progress, and clock events
- Events stored in device_data_t structure

### Progress Reporting
- Real-time dive counting as logs are processed
- Accurate representation of discovered dives
- UI updates as each dive is parsed
- No dependency on device-reported progress

### Fingerprint Implementation
- Stores fingerprint of most recent dive
- Uses UserDefaults for persistence
- Speeds up subsequent downloads
- Set via dc_device_set_fingerprint()

## Common Operations

### Retrieving Dive Logs
1. Connect to device via BLE
2. Open device using libdivecomputer
3. Enumerate dives using dc_device_foreach
4. Parse dive data using suunto_eonsteel_parser
5. Display results in UI

### Error Handling
- Validates device connections
- Checks parsing status
- Reports errors in UI
- Handles BLE disconnections

## Future Improvements
1. Implement dive profile visualization
2. Add support for dive log storage
3. Add cancellation support via device_set_cancel()
4. Implement multi-device handling

## BLE Transfer Optimizations
- Reduced polling intervals from 100ms to 10ms.
- Shortened timeouts for faster error detection.
- Added transfer rate monitoring.
- Immediate buffer processing of received data.
- Thread-safe buffer management with minimal blocking.

## Dynamic BLE Service Discovery
- The application now implements a dynamic approach to discover BLE services and characteristics.
- It first attempts to discover known service UUIDs for specific manufacturers (e.g., Shearwater, Suunto).
- If no known services are found, it falls back to discovering all available services.
- The application identifies valid services based on the presence of both write and notify characteristics.
- This approach enhances compatibility with various BLE devices without hardcoding specific UUIDs.

## Build Configuration Notes

### Linking Configuration
- Ensure all C functions are properly declared with extern "C" when used in C++ context.
- Key functions like `identify_ble_device` and `open_ble_device` must be included in build.
- BLEBridge and configuredc headers must be properly exported.

## Dependency Management

### libdivecomputer Integration
- Included as Git submodule in Vendors/libdivecomputer.
- Version locked to 0.8.0 via Package.resolved.
- Exposed through Clibdivecomputer module.
- Headers accessible via modular imports.

### Build Configuration
- Minimum deployment targets: iOS 15, macOS 12.
- Uses module maps for C library integration.
- Automatic version management through SPM.

### Submodule Management
- Update submodule: git submodule update --remote.
- Initial clone: git clone --recursive [repo-url].
- Post-clone setup: git submodule init && git submodule update.

### Git Configuration
- .gitignore configured to exclude:
  - Xcode project files.
  - macOS system files.
  - Build artifacts.
  - Swift Package Manager files.
- Manual cleanup may be needed for previously tracked files.

## Development and Distribution

### Package Structure
- LibDCSwift: Main Swift library for dive computer communication.
- LibDCBridge: Objective-C bridge to libdivecomputer.
- Clibdivecomputer: C library wrapper.

### Headers
- libdcswift-bridging-header.h: Main bridging header.
- BLEBridge.h: Bluetooth functionality bridge.
- configuredc.h: Device configuration bridge.

### Development
1. Open `libdc-swift.xcworkspace`.
2. Both package and test app are available.
3. Use built-in test app for quick testing.
4. Use standalone test app for full app testing.

### Distribution
When distributing as a package:
- Only LibDCSwift and LibDCBridge are exposed.
- Test apps are excluded.
- Headers are properly bundled.

# fyi

## BLEBridge and Swift bridging
- Removed "@import LibDCSwift" from BLEBridge.m to prevent module not found errors.
- Added a forward declaration of "CoreBluetoothManager" in BLEBridge.m so that Objective-C can call the Swift class directly.

## Logger Integration
- Moved Logger.swift into Sources/LibDCSwift directory for proper target inclusion.
- Logger functions (logDebug, logError, etc.) are now available throughout the LibDCSwift target.

## Platform Support
- Updated minimum deployment targets to iOS 15 and macOS 12.
- Required for Combine framework features (@Published, ObservableObject).
- Ensures compatibility with SwiftUI and modern iOS/macOS features.

## Access Control
- Public properties in CoreBluetoothManager:
  - shared (static instance).
  - centralManager.
  - peripheral.
  - discoveredPeripherals.
  - isPeripheralReady.
  - connectedDevice.
  - isScanning.
- Properties need public access for use in client applications.
- @Published properties must be marked public to be observable outside the module.

## Source Files Organization
- Models:
  - DiveData.swift: Core data structure for dive information.
  - DeviceConfiguration.swift: Device setup and configuration.
- ViewModels:
  - DiveDataViewModel.swift: Manages dive data state and operations.
- Core:
  - BLEManager.swift: Bluetooth communication.
  - Logger.swift: Logging functionality.

## Observable Properties in CoreBluetoothManager
- @Published properties:
  - centralManager.
  - peripheral.
  - discoveredPeripherals.
  - isPeripheralReady.
  - connectedDevice.
  - isScanning.
  - openedDeviceDataPtr (with willSet observer).
- Properties are observable in SwiftUI views.
- Changes trigger view updates automatically.
- Unsafe pointer properties need special handling for observation.

## Objective-C Interop
- CoreBluetoothManager needs @objc(CoreBluetoothManager) attribute for proper Objective-C visibility.
- BLEBridge.h must declare the Swift class with @class.
- Ensure Swift class name matches Objective-C expectations.
- All methods called from Objective-C must have @objc attribute.

## Generic Parser Setup

A new generic parser implementation has been added to simplify dive data processing:

- `GenericParser.swift`: Centralizes parsing logic for all supported device families
- Uses existing `DiveData` structure for parsed dive information
- Parser automatically handles different device types and sample processing
- Error handling with specific ParserError cases for better debugging
- Thread-safe implementation with proper memory management