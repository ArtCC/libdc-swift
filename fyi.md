# BLE Test Application Overview

This codebase implements a Bluetooth Low Energy (BLE) application for communicating with Suunto EON Steel and D5 dive computers.

## Key Files and Their Purposes

### Core Components
- **BLEManager.swift**: Handles BLE communication and device management
- **BluetoothScanView.swift**: Main UI for scanning and connecting to devices
- **ConnectedDeviceView.swift**: Handles dive log retrieval and display
- **DiveDataViewModel.swift**: Manages dive data and state
- **DiveLogSettingsView.swift**: Manages fingerprint and device settings

### Protocol Implementation
- **configuredc.c**: Bridge between Swift and libdivecomputer
- **DiveLogRetriever.swift**: Handles dive log downloading and parsing
- **GenericParser.swift**: Parses dive data from different device families

## Key Features

### Fingerprint Implementation
- Stores fingerprint of most recent dive
- Uses UserDefaults for persistence
- Speeds up subsequent downloads
- Set via dc_device_set_fingerprint()
- Toggle in settings to enable/disable fingerprint usage

### Device Management
- Stores connected device information
- Tracks first connection date
- Allows manual device forgetting
- Persists device settings

### Progress Reporting
- Real-time dive counting as logs are processed
- Accurate representation of discovered dives
- UI updates as each dive is parsed
- Timer-based progress monitoring

## Common Operations

### Retrieving Dive Logs
1. Connect to device via BLE
2. Open device using libdivecomputer
3. Set fingerprint if enabled
4. Enumerate dives using dc_device_foreach
5. Parse dive data using appropriate parser
6. Display results in UI

### Error Handling
- Validates device connections
- Checks parsing status
- Reports detailed errors in UI
- Handles BLE disconnections
- Provides status codes in error messages

## Future Work

### High Priority
1. Fix dive enumeration issues:
   - Investigate why dives aren't being enumerated
   - Add more detailed logging for dive callbacks
   - Verify parser creation and usage
   - Test with different device states

2. Improve Fingerprint System:
   - Add ability to manually set fingerprint
   - Better fingerprint validation
   - Visual indicator for fingerprint status
   - Fingerprint history tracking

3. Enhance Error Handling:
   - More detailed error messages
   - Recovery suggestions
   - Automatic retry mechanisms
   - Connection state recovery

### Medium Priority
1. Data Management:
   - Local storage for dive logs
   - Export functionality
   - Backup/restore capabilities
   - Data synchronization

2. UI Improvements:
   - Dive profile visualization
   - Better progress indicators
   - Detailed dive statistics
   - Custom dive log filters

3. Device Support:
   - Add support for more dive computers
   - Better device identification
   - Multiple device management
   - Device-specific settings

## Known Issues
1. Dive enumeration not working properly
2. Fingerprint toggle needs improvement
3. Progress reporting could be more accurate
4. Error messages need more detail
5. Device identification could be more robust

## Memory Management Notes
- Device pointers must be properly managed
- Parsers need to be cleaned up after use
- Contexts must be released appropriately
- Avoid retaining C pointers longer than needed