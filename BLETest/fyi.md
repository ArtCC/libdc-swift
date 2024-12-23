# BLE Test Application Overview

This codebase implements a Bluetooth Low Energy (BLE) application for communicating with Suunto EON Steel and D5 dive computers.

## Key Files and Their Purposes

### Core Components
- **BLEManager.swift**: Handles BLE communication and device management
- **BluetoothScanView.swift**: Main UI for scanning and connecting to devices
- **ConnectedDeviceView.swift**: Handles dive log retrieval and display
- **DiveDataViewModel.swift**: Manages dive data and state

### Protocol Implementation
- **configuredc.c**: Bridge between Swift and libdivecomputer
- **suunto_eonsteel.c**: Suunto-specific protocol implementation

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
- Reduced polling intervals from 100ms to 10ms
- Shortened timeouts for faster error detection
- Added transfer rate monitoring
- Immediate buffer processing of received data
- Thread-safe buffer management with minimal blocking